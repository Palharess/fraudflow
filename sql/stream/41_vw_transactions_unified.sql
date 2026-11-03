-- ===========================================================================
-- 41 · Visão unificada: histórico (batch) + tempo real (stream)
--
-- Uma consulta só enxerga as duas fontes como uma tabela. A coluna origin diz
-- de onde veio cada linha, e arrived_at quando ela chegou ao BigQuery.
--
-- As duas fontes cobrem períodos seguidos: o batch é o fraudTrain, até
-- 21/06/2020 às 12:13; o stream reproduz o fraudTest, que começa logo depois.
--
-- Duplicatas: o lado batch já sai único da Silver. O lado stream pode repetir
-- uma transação, porque o Pub/Sub entrega cada mensagem pelo menos uma vez e o
-- gerador pode ser reiniciado. A view mantém a primeira chegada de cada
-- transaction_id. A tabela física continua com as repetições, que ficam
-- visíveis para auditoria.
--
-- O rótulo is_fraud só existe no batch. No stream ele é nulo: na vida real, o
-- rótulo chega dias depois, com a contestação da compra.
-- ===========================================================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.gold.vw_transactions_unified`
OPTIONS (description = 'Transações do histórico (batch) e do tempo real (stream), sem duplicatas')
AS
SELECT
  'batch'               AS origin,
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
  ingestion_timestamp   AS arrived_at
FROM `${PROJECT_ID}.silver.transactions`

UNION ALL

(
SELECT
  'stream'              AS origin,
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
  CAST(NULL AS INT64)   AS is_fraud,
  processed_at          AS arrived_at
FROM `${PROJECT_ID}.silver.transactions_stream`
WHERE TRUE
-- Primeira chegada de cada transação; empate resolvido pelo id da mensagem.
QUALIFY ROW_NUMBER() OVER (
          PARTITION BY transaction_id
          ORDER BY processed_at, pubsub_message_id
        ) = 1
);
