-- ===========================================================================
-- 20 · gold.ml_input
--
-- Repassa os campos canônicos da Silver, mais o rótulo. NENHUMA feature é
-- calculada aqui: elas nascem inteiras dentro do TRANSFORM do CREATE MODEL,
-- para viajarem junto com o modelo quando ele for para o Vertex AI.
--
-- Esta tabela é o espelho exato do contrato do evento do Trabalho 2. Se um
-- campo não está aqui, a API de outubro não vai tê-lo.
-- ===========================================================================

CREATE OR REPLACE TABLE `${PROJECT_ID}.gold.ml_input`
PARTITION BY DATE(transaction_ts)
AS
SELECT
  -- identificador: não é feature, serve para juntar o rótulo depois da
  -- predição e para auditar um caso específico na demo
  transaction_id,

  -- ---- os dez campos do contrato ----
  transaction_ts,
  customer_dob,
  customer_lat,
  customer_long,
  merchant_lat,
  merchant_long,
  amount,
  category,
  city_pop,

  -- ---- rótulo ----
  is_fraud,

  -- Chave de corte temporal em texto, no formato 'YYYY-MM-DD HH:MM:SS'.
  -- Neste formato a ordem alfabética é a ordem cronológica, então o recorte
  -- do DATA_SPLIT_METHOD='SEQ' fica idêntico ao que sairia do TIMESTAMP.
  -- Existe como alternativa pronta caso o registro no Vertex AI recuse
  -- TIMESTAMP na entrada do modelo — ver o notebook 04.
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', transaction_ts)  AS split_key

FROM `${PROJECT_ID}.silver.transactions`;
