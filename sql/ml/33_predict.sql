-- ===========================================================================
-- 33 · Predição — a demo ao vivo
--
-- Repare na estrutura: o modelo recebe SÓ os campos do contrato, sem
-- is_fraud. O rótulo entra depois, por um JOIN em transaction_id, apenas para
-- mostrar acerto e erro na tela.
--
-- E a mesma separacao que a API do Trabalho 2 tera: la o evento chega sem
-- rotulo nenhum, e o modelo precisa decidir sozinho.
--
-- O recorte é o período de validação — os 20% finais por tempo, que o
-- DATA_SPLIT_METHOD='SEQ' reservou e o modelo nunca viu no treino.
-- ===========================================================================

WITH corte AS (
  SELECT APPROX_QUANTILES(transaction_ts, 5)[OFFSET(4)] AS inicio_validacao
  FROM `${PROJECT_ID}.gold.ml_input`
),

-- Só os campos do contrato. Nenhum rótulo passa por aqui.
evento AS (
  SELECT
    transaction_id,
    transaction_ts,
    customer_dob,
    customer_lat,
    customer_long,
    merchant_lat,
    merchant_long,
    amount,
    category,
    city_pop
  FROM `${PROJECT_ID}.gold.ml_input`, corte
  WHERE transaction_ts >= corte.inicio_validacao
),

pontuado AS (
  SELECT
    transaction_id,
    transaction_ts,
    amount,
    category,
    (SELECT p.prob
     FROM UNNEST(predicted_is_fraud_probs) AS p
     WHERE CAST(p.label AS STRING) = '1')                 AS fraud_score
  FROM ML.PREDICT(MODEL `${PROJECT_ID}.gold.fraud_boosted`,
                  (SELECT * FROM evento))
)

-- O rótulo só encosta na predição AGORA, depois da inferência.
SELECT
  FORMAT_TIMESTAMP('%d/%m %H:%M', p.transaction_ts)       AS quando,
  p.category                                              AS categoria,
  ROUND(p.amount, 2)                                      AS valor,
  ROUND(p.fraud_score, 4)                                 AS fraud_score,
  IF(p.fraud_score >= 0.30, 'FRAUD', 'LEGIT')             AS decisao,
  r.is_fraud                                              AS rotulo_real,
  IF((p.fraud_score >= 0.30) = (r.is_fraud = 1), 'ok', 'ERRO') AS resultado
FROM pontuado AS p
JOIN `${PROJECT_ID}.gold.ml_input` AS r
  USING (transaction_id)
ORDER BY p.fraud_score DESC
LIMIT 20;
