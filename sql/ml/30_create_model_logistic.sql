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

  -- Haversine sobre o elipsoide, em quilômetros.
  ST_DISTANCE(
    ST_GEOGPOINT(customer_long, customer_lat),
    ST_GEOGPOINT(merchant_long, merchant_lat)
  ) / 1000.0                                              AS distance_km,

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

  -- Já registra e versiona no Vertex AI. Não custa nada enquanto não houver
  -- endpoint implantado, e adianta metade do Trabalho 2.
  MODEL_REGISTRY           = 'VERTEX_AI',
  VERTEX_AI_MODEL_ID       = 'fraudflow-logistic'
) AS
SELECT * EXCEPT (transaction_id, split_key)
FROM `${PROJECT_ID}.gold.ml_input`;


-- ===========================================================================
-- TESTE DO DIA 8 — o risco que o plano mandou verificar
--
-- Incerteza: TIMESTAMP na posição de DATA_SPLIT_COL dentro do TRANSFORM pode
-- ser recusado na hora de registrar o modelo no Vertex AI. Não conseguimos
-- confirmar na documentação, e é justamente a peça de que o Trabalho 2
-- depende — então confirmamos agora, não em outubro.
--
-- Como testar: rodar este arquivo e conferir se o modelo aparece em
-- Vertex AI > Model Registry com o id 'fraudflow-logistic'.
--
-- SE FALHAR, troque exatamente três linhas para a alternativa em texto.
-- A gold.ml_input já traz a coluna split_key pronta, no formato
-- 'YYYY-MM-DD HH:MM:SS', cuja ordem alfabética é a ordem cronológica — o
-- recorte temporal fica idêntico e o TIMESTAMP sai da entrada do modelo.
--
--   1. no TRANSFORM, troque      transaction_ts        por   split_key
--   2. em OPTIONS, troque        DATA_SPLIT_COL = 'transaction_ts'
--                                por  DATA_SPLIT_COL = 'split_key'
--   3. no SELECT final, troque   EXCEPT (transaction_id, split_key)
--                                por  EXCEPT (transaction_id, transaction_ts)
--
-- Atenção ao passo 3: sem ele, transaction_ts continuaria disponível e o
-- TRANSFORM precisaria dele para calcular hour, day_of_week, is_night e age.
-- Ou seja, mantenha transaction_ts na ENTRADA e apenas troque o que é
-- repassado na SAÍDA do TRANSFORM:
--
--   TRANSFORM ( ..., FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', transaction_ts)
--                      AS split_key, is_fraud )
--   OPTIONS   ( ..., DATA_SPLIT_COL = 'split_key' )
--   AS SELECT * EXCEPT (transaction_id, split_key) FROM gold.ml_input
-- ===========================================================================
