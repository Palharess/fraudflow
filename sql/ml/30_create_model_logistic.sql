-- ===========================================================================
-- 30 · Modelo v1 — regressão logística (baseline)
--
-- TODAS as features do modelo nascem aqui dentro, no TRANSFORM. Esse é o
-- ponto central da arquitetura: o TRANSFORM é serializado junto com o modelo,
-- então quando ele for para o Vertex AI em outubro, a API vai aplicar
-- exatamente este código — não uma reimplementação em Python que diverge.
--
-- A entrada é gold.ml_input, que é o espelho do contrato do evento do T2.
-- ===========================================================================

CREATE OR REPLACE MODEL `${PROJECT_ID}.gold.fraud_logistic`

TRANSFORM (
  ------------------------------------------------------------------ features
  amount,
  LN(amount)                                              AS log_amount,
  category,

  EXTRACT(HOUR      FROM transaction_ts)                  AS hour,
  EXTRACT(DAYOFWEEK FROM transaction_ts)                  AS day_of_week,
  (EXTRACT(HOUR FROM transaction_ts) >= 22
   OR EXTRACT(HOUR FROM transaction_ts) <= 3)             AS is_night,

  -- Idade completa na data da compra. O DATE_DIFF com YEAR conta viradas de
  -- ano, não anos completos, então descontamos 1 quando o aniversário ainda
  -- não passou. Calculada a partir de transaction_ts — NUNCA do unix_time,
  -- que deixaria todo mundo sete anos mais novo sem emitir erro.
  DATE_DIFF(DATE(transaction_ts), customer_dob, YEAR)
    - IF(FORMAT_DATE('%m%d', DATE(transaction_ts))
          < FORMAT_DATE('%m%d', customer_dob), 1, 0)      AS age,

  -- Haversine em km. Escrito com ATAN2/SIN/COS/SQRT/POW de proposito:
  -- ST_DISTANCE e ST_GEOGPOINT NAO constam na lista de funcoes que o BigQuery
  -- aceita dentro do TRANSFORM ao exportar/implantar o modelo, e GEOGRAPHY e
  -- um tipo proibido nesse caminho. Com ST_* o modelo TREINA normalmente, mas
  -- o deploy no Vertex AI em outubro fica em risco. ACOS(-1) e o pi.
  2 * 6371.0 * ATAN2(
    SQRT(
      POW(SIN((merchant_lat - customer_lat) * ACOS(-1) / 360), 2)
      + COS(customer_lat * ACOS(-1) / 180)
        * COS(merchant_lat * ACOS(-1) / 180)
        * POW(SIN((merchant_long - customer_long) * ACOS(-1) / 360), 2)
    ),
    SQRT(1 -
      ( POW(SIN((merchant_lat - customer_lat) * ACOS(-1) / 360), 2)
        + COS(customer_lat * ACOS(-1) / 180)
          * COS(merchant_lat * ACOS(-1) / 180)
          * POW(SIN((merchant_long - customer_long) * ACOS(-1) / 360), 2) )
    )
  )                                                       AS distance_km,

  city_pop,

  --------------------------------------------------- passagem sem transformar
  -- Coluna de corte temporal. Precisa sair do TRANSFORM sem alteração para
  -- o DATA_SPLIT_COL enxergá-la. Não é feature.
  transaction_ts,

  -- Rótulo.
  is_fraud
)

OPTIONS (
  MODEL_TYPE               = 'LOGISTIC_REG',
  INPUT_LABEL_COLS         = ['is_fraud'],

  -- Fraude é ~0,5% dos casos. Sem reponderar, o modelo aprende a responder
  -- "não é fraude" sempre e exibe 99,5% de acurácia sem ter aprendido nada.
  AUTO_CLASS_WEIGHTS       = TRUE,

  -- Recorte temporal: ordena pela coluna indicada e reserva as últimas linhas
  -- para validação. Treina no passado, valida no período mais recente.
  DATA_SPLIT_METHOD        = 'SEQ',
  DATA_SPLIT_COL           = 'transaction_ts',
  DATA_SPLIT_EVAL_FRACTION = 0.20,

  -- Registra e versiona no Vertex AI. Nao ha custo enquanto nao houver
  -- endpoint implantado.
  MODEL_REGISTRY           = 'VERTEX_AI',
  VERTEX_AI_MODEL_ID       = 'fraudflow-logistic'
) AS
SELECT * EXCEPT (transaction_id, split_key)
FROM `${PROJECT_ID}.gold.ml_input`;
