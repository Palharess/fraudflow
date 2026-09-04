-- ===========================================================================
-- Camada Silver — campos canônicos
--
-- Uma consulta só, executada dentro do BigQuery. 1,3 milhão de linhas são
-- lidas, transformadas e gravadas sem sair de lá: o notebook manda a ordem e
-- recebe a confirmação.
--
-- O que acontece:
--   1. tipagem com SAFE_CAST e SAFE.PARSE_* (o que não converte vira NULL)
--   2. resolução do conflito de sete anos entre as duas colunas de tempo
--   3. remoção do prefixo fraud_ dos comerciantes
--   4. descarte contável das linhas inválidas
--   5. deduplicação por trans_num
--
-- NENHUMA feature de modelo. Distância, idade e período do dia nascem no
-- TRANSFORM do CREATE MODEL, para viajarem junto com o modelo até o Vertex AI.
-- ===========================================================================

CREATE OR REPLACE TABLE `${PROJECT_ID}.silver.transactions`
PARTITION BY DATE(transaction_ts)
CLUSTER BY category
AS
WITH tipado AS (
  SELECT
    -- ---- identificação ----
    trans_num                                          AS transaction_id,
    cc_num                                             AS card_id,

    -- ---- tempo ----
    -- ARMADILHA: trans_date_trans_time diz 2019-2020 e unix_time, na MESMA
    -- linha, diz 2012-2013 — deslocamento constante de 2557 dias.
    -- trans_date_trans_time é a única fonte de tempo do projeto, e unix_time
    -- não é sequer lido aqui.
    SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S',
                         trans_date_trans_time)        AS transaction_ts,

    -- ---- transação ----
    SAFE_CAST(amt AS FLOAT64)                          AS amount,
    category                                           AS category,
    -- os 693 comerciantes vêm com o prefixo fraud_, inclusive em transação
    -- legítima. É artefato do gerador, não vazamento — mas confunde e convida
    -- a filtro acidental.
    REGEXP_REPLACE(merchant, r'^fraud_', '')           AS merchant_name,

    -- ---- perfil do cliente (contexto estático do contrato do T2) ----
    SAFE.PARSE_DATE('%Y-%m-%d', dob)                   AS customer_dob,
    SAFE_CAST(lat AS FLOAT64)                          AS customer_lat,
    SAFE_CAST(`long` AS FLOAT64)                       AS customer_long,
    state                                              AS customer_state,
    SAFE_CAST(city_pop AS INT64)                       AS city_pop,

    -- ---- comerciante ----
    SAFE_CAST(merch_lat AS FLOAT64)                    AS merchant_lat,
    SAFE_CAST(merch_long AS FLOAT64)                   AS merchant_long,

    -- ---- rótulo e linhagem ----
    SAFE_CAST(is_fraud AS INT64)                       AS is_fraud,
    ingestion_timestamp,
    source_file

    -- Ausentes de propósito: unix_time (deslocado sete anos) e first, last,
    -- street, zip, gender e job — dados pessoais que o grupo decidiu não usar
    -- para decidir fraude. Não trazê-los torna a escolha verificável.
  FROM `${PROJECT_ID}.bronze.transactions`
)

SELECT
  transaction_id,
  card_id,
  transaction_ts,
  amount,
  category,
  merchant_name,
  customer_dob,
  customer_lat,
  customer_long,
  customer_state,
  city_pop,
  merchant_lat,
  merchant_long,
  is_fraud,
  ingestion_timestamp,
  source_file
FROM tipado
WHERE transaction_ts IS NOT NULL
  AND amount IS NOT NULL AND amount > 0
  AND customer_dob IS NOT NULL
  AND customer_dob < DATE(transaction_ts)
  AND customer_lat  BETWEEN  -90 AND  90
  AND customer_long BETWEEN -180 AND 180
  AND merchant_lat  BETWEEN  -90 AND  90
  AND merchant_long BETWEEN -180 AND 180
  AND is_fraud IN (0, 1)
-- Uma linha por transação. Em empate, fica a primeira ingerida.
QUALIFY ROW_NUMBER() OVER (
          PARTITION BY transaction_id
          ORDER BY ingestion_timestamp, source_file
        ) = 1;
