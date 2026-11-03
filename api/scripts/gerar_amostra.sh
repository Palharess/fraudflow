#!/usr/bin/env bash
# Gera api/teste/amostra.json: 25 fraudes e 25 legítimas da janela de validação
# do treino, com o score do ML.PREDICT e as features do ML.TRANSFORM como
# referência (colunas f_*). O holdout não é usado.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
DESTINO="$(cd "$(dirname "$0")/.." && pwd)/teste"
mkdir -p "$DESTINO"

read -r -d '' SQL <<EOF || true
WITH corte AS (
  SELECT APPROX_QUANTILES(transaction_ts, 5)[OFFSET(4)] AS inicio_validacao
  FROM \`${PROJECT_ID}.gold.ml_input\`
),
validacao AS (
  SELECT m.*
  FROM \`${PROJECT_ID}.gold.ml_input\` AS m, corte
  WHERE m.transaction_ts >= corte.inicio_validacao
),
amostra AS (
  (SELECT * FROM validacao WHERE is_fraud = 1
   ORDER BY FARM_FINGERPRINT(transaction_id) LIMIT 25)
  UNION ALL
  (SELECT * FROM validacao WHERE is_fraud = 0
   ORDER BY FARM_FINGERPRINT(transaction_id) LIMIT 25)
),
referencia AS (
  SELECT
    transaction_id,
    (SELECT p.prob FROM UNNEST(predicted_is_fraud_probs) AS p
     WHERE CAST(p.label AS STRING) = '1')                  AS score_bq
  FROM ML.PREDICT(
    MODEL \`${PROJECT_ID}.gold.fraud_boosted\`,
    (SELECT transaction_id, transaction_ts, customer_dob, customer_lat,
            customer_long, merchant_lat, merchant_long, amount, category,
            city_pop
     FROM amostra))
),
-- O ML.TRANSFORM devolve só as colunas do TRANSFORM, sem o transaction_id.
-- A ligação com a amostra usa as colunas que o TRANSFORM repassa sem mudar.
features AS (
  SELECT * FROM ML.TRANSFORM(
    MODEL \`${PROJECT_ID}.gold.fraud_boosted\`,
    (SELECT * EXCEPT (transaction_id, split_key) FROM amostra))
)
SELECT
  a.transaction_id,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', a.transaction_ts) AS transaction_ts,
  CAST(a.customer_dob AS STRING)                          AS customer_dob,
  a.customer_lat, a.customer_long, a.merchant_lat, a.merchant_long,
  a.amount, a.category, a.city_pop,
  a.is_fraud,
  r.score_bq,
  f.amount      AS f_amount,
  f.log_amount  AS f_log_amount,
  f.category    AS f_category,
  f.hour        AS f_hour,
  f.day_of_week AS f_day_of_week,
  f.is_night    AS f_is_night,
  f.age         AS f_age,
  f.distance_km AS f_distance_km,
  f.city_pop    AS f_city_pop
FROM amostra AS a
JOIN referencia AS r USING (transaction_id)
LEFT JOIN features AS f
  ON  f.transaction_ts = a.transaction_ts
  AND f.amount = a.amount
  AND f.category = a.category
ORDER BY a.is_fraud DESC, a.transaction_id
EOF

bq --project_id="$PROJECT_ID" --location=us-central1 query \
  --use_legacy_sql=false --format=json --max_rows=100 "$SQL" > "$DESTINO/amostra.json"

echo "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$DESTINO/amostra.json") transações em $DESTINO/amostra.json"
