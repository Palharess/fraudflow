-- ===========================================================================
-- 40 · Tabelas do streaming
--
-- O Dataflow grava aqui as transações que chegam pelo Pub/Sub. As tabelas
-- ficam dentro das camadas que já existem: o stream é a mesma Silver, só que
-- chegando em tempo real.
--
-- silver.transactions_stream: mesmas colunas canônicas da silver.transactions,
-- mesma partição (data da transação) e mesmo cluster (categoria). Sem is_fraud:
-- o evento chega sem rótulo. Três colunas a mais contam a viagem do evento:
-- quando foi publicado, quando foi processado e o id da mensagem.
--
-- silver.transactions_stream_errors: o que o pipeline recusou, com o motivo e
-- o evento original. Particionada pela data de processamento, que é como a
-- operação consulta erros.
-- ===========================================================================

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.silver.transactions_stream` (
  transaction_id    STRING    NOT NULL,
  card_id           STRING,
  transaction_ts    TIMESTAMP NOT NULL  OPTIONS (description = 'Horário da transação (event time)'),
  amount            FLOAT64,
  category          STRING,
  merchant_name     STRING,
  customer_dob      DATE,
  customer_lat      FLOAT64,
  customer_long     FLOAT64,
  customer_state    STRING,
  city_pop          INT64,
  merchant_lat      FLOAT64,
  merchant_long     FLOAT64,
  published_at      TIMESTAMP OPTIONS (description = 'Quando o gerador publicou no Pub/Sub'),
  processed_at      TIMESTAMP NOT NULL  OPTIONS (description = 'Quando o Dataflow processou (processing time)'),
  pubsub_message_id STRING
)
PARTITION BY DATE(transaction_ts)
CLUSTER BY category
OPTIONS (description = 'Transações recebidas em streaming (Pub/Sub → Dataflow), já limpas');

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.silver.transactions_stream_errors` (
  processed_at      TIMESTAMP NOT NULL,
  error_reason      STRING    NOT NULL,
  transaction_id    STRING,
  raw_payload       STRING    OPTIONS (description = 'Evento como chegou, para diagnóstico'),
  pubsub_message_id STRING
)
PARTITION BY DATE(processed_at)
OPTIONS (
  description = 'Eventos recusados pelo pipeline de streaming, com o motivo',
  partition_expiration_days = 30
);
