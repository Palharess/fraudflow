-- ===========================================================================
-- 42 · Consultas da demonstração ao vivo
--
-- Rodar no console do BigQuery, uma de cada vez, com o gerador e o Dataflow
-- ligados. Substitua ${PROJECT_ID} pelo id do projeto.
-- ===========================================================================


-- 1. As duas origens lado a lado. Rode duas vezes com alguns segundos de
--    intervalo: a linha stream cresce, a batch fica parada.
SELECT
  origin,
  COUNT(*)            AS transacoes,
  MIN(transaction_ts) AS primeira_transacao,
  MAX(transaction_ts) AS ultima_transacao,
  MAX(arrived_at)     AS ultima_chegada
FROM `${PROJECT_ID}.gold.vw_transactions_unified`
GROUP BY origin
ORDER BY origin;


-- 2. A emenda: onde o histórico termina e o tempo real começa, em 21/06/2020.
--    O filtro na data usa a partição das duas tabelas.
SELECT
  origin,
  FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S', transaction_ts) AS quando,
  category,
  ROUND(amount, 2) AS valor,
  is_fraud
FROM `${PROJECT_ID}.gold.vw_transactions_unified`
WHERE DATE(transaction_ts) = '2020-06-21'
  AND transaction_ts BETWEEN '2020-06-21 12:10:00' AND '2020-06-21 12:20:00'
ORDER BY transaction_ts;


-- 3. Atraso do pipeline: do momento em que o gerador publicou até o Beam
--    começar a processar o evento (processed_at é marcado antes da gravação
--    no BigQuery), nos eventos dos últimos 10 minutos.
SELECT
  COUNT(*)                                                          AS eventos,
  ROUND(AVG(TIMESTAMP_DIFF(processed_at, published_at, MILLISECOND))) AS atraso_medio_ms,
  APPROX_QUANTILES(TIMESTAMP_DIFF(processed_at, published_at, MILLISECOND), 100)[OFFSET(95)]
                                                                    AS atraso_p95_ms
FROM `${PROJECT_ID}.silver.transactions_stream`
WHERE processed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);


-- 4. O que a limpeza recusou, por motivo, com um exemplo de cada.
SELECT
  error_reason,
  COUNT(*)                 AS eventos,
  ANY_VALUE(raw_payload)   AS exemplo
FROM `${PROJECT_ID}.silver.transactions_stream_errors`
WHERE DATE(processed_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY error_reason
ORDER BY eventos DESC;


-- 5. Duplicatas: a tabela física guarda reenvios, a view entrega cada
--    transação uma vez.
SELECT
  (SELECT COUNT(*) FROM `${PROJECT_ID}.silver.transactions_stream`)                  AS linhas_na_tabela,
  (SELECT COUNT(DISTINCT transaction_id) FROM `${PROJECT_ID}.silver.transactions_stream`) AS transacoes_distintas,
  (SELECT COUNT(*) FROM `${PROJECT_ID}.gold.vw_transactions_unified` WHERE origin = 'stream') AS linhas_na_view;


-- 6. Processamento por minuto: o ritmo em que o stream chega.
SELECT
  TIMESTAMP_TRUNC(processed_at, MINUTE) AS minuto,
  COUNT(*)                              AS eventos
FROM `${PROJECT_ID}.silver.transactions_stream`
WHERE processed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 MINUTE)
GROUP BY minuto
ORDER BY minuto DESC;


-- 7. As últimas transações que chegaram na Silver de streaming: o horário da
--    compra (2020, o original) ao lado do horário de chegada (agora, no fuso
--    de Brasília). Rode duas vezes: as do topo mudam.
SELECT
  FORMAT_TIMESTAMP('%H:%M:%S', processed_at, 'America/Sao_Paulo') AS chegou_as,
  FORMAT_TIMESTAMP('%d/%m/%Y %H:%M', transaction_ts)               AS horario_da_compra,
  category,
  ROUND(amount, 2)                                                 AS valor,
  merchant_name,
  customer_state
FROM `${PROJECT_ID}.silver.transactions_stream`
WHERE processed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
ORDER BY processed_at DESC
LIMIT 10;
