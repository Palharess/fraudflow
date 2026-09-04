-- ===========================================================================
-- 31 · Modelo v2 — árvores impulsionadas
--
-- TRANSFORM idêntico ao do v1, de propósito: a comparação entre os dois
-- modelos só é honesta se as features forem exatamente as mesmas. O que muda
-- é o algoritmo.
--
-- CUSTO: este é o único gasto imprevisível do Trabalho 1. Treino de modelo
-- tem tarifa própria e não entra na cota gratuita, e o boosted tree tem um
-- componente cobrado à parte. Abra o Billing logo depois deste treino.
-- ===========================================================================

CREATE OR REPLACE MODEL `${PROJECT_ID}.gold.fraud_boosted`

TRANSFORM (
  amount,
  LN(amount)                                              AS log_amount,
  category,

  EXTRACT(HOUR      FROM transaction_ts)                  AS hour,
  EXTRACT(DAYOFWEEK FROM transaction_ts)                  AS day_of_week,
  (EXTRACT(HOUR FROM transaction_ts) >= 22
   OR EXTRACT(HOUR FROM transaction_ts) <= 3)             AS is_night,

  DATE_DIFF(DATE(transaction_ts), customer_dob, YEAR)
    - IF(FORMAT_DATE('%m%d', DATE(transaction_ts))
          < FORMAT_DATE('%m%d', customer_dob), 1, 0)      AS age,

  ST_DISTANCE(
    ST_GEOGPOINT(customer_long, customer_lat),
    ST_GEOGPOINT(merchant_long, merchant_lat)
  ) / 1000.0                                              AS distance_km,

  city_pop,

  transaction_ts,
  is_fraud
)

OPTIONS (
  MODEL_TYPE               = 'BOOSTED_TREE_CLASSIFIER',
  BOOSTER_TYPE             = 'GBTREE',
  TREE_METHOD              = 'HIST',
  MAX_ITERATIONS           = 50,
  EARLY_STOP               = TRUE,
  SUBSAMPLE                = 0.85,
  MAX_TREE_DEPTH           = 8,

  INPUT_LABEL_COLS         = ['is_fraud'],
  AUTO_CLASS_WEIGHTS       = TRUE,

  DATA_SPLIT_METHOD        = 'SEQ',
  DATA_SPLIT_COL           = 'transaction_ts',
  DATA_SPLIT_EVAL_FRACTION = 0.20,

  MODEL_REGISTRY           = 'VERTEX_AI',
  VERTEX_AI_MODEL_ID       = 'fraudflow-boosted'
) AS
SELECT * EXCEPT (transaction_id, split_key)
FROM `${PROJECT_ID}.gold.ml_input`;

-- Se o teste do dia 8 exigir a troca para split_key, aplique aqui a mesma
-- alteração descrita no rodapé de 30_create_model_logistic.sql.
