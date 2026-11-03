#!/usr/bin/env bash
# Prepara o streaming. Pode rodar mais de uma vez: o que já existe é mantido.
#
#   1. APIs do Pub/Sub e do Dataflow
#   2. tópico transactions e assinatura transactions-dataflow
#   3. tabelas silver.transactions_stream e _errors, e a view unificada
#   4. conta de serviço do Dataflow, só com os papéis necessários
#
# Uso, da raiz do repositório: bash infra/setup_streaming.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
REGION="${REGION:-us-central1}"
BUCKET="${BUCKET:-fraudflow-pdm-gps-data}"
TOPICO="transactions"
ASSINATURA="transactions-dataflow"
CONTA="fraudflow-dataflow@${PROJECT_ID}.iam.gserviceaccount.com"

echo "== APIs"
gcloud services enable pubsub.googleapis.com dataflow.googleapis.com --project="$PROJECT_ID"

echo "== Pub/Sub"
gcloud pubsub topics describe "$TOPICO" --project="$PROJECT_ID" >/dev/null 2>&1 ||
  gcloud pubsub topics create "$TOPICO" --project="$PROJECT_ID"
# Mensagens não confirmadas ficam guardadas por um dia: se o Dataflow estiver
# parado, o que o gerador publicar espera por ele.
gcloud pubsub subscriptions describe "$ASSINATURA" --project="$PROJECT_ID" >/dev/null 2>&1 ||
  gcloud pubsub subscriptions create "$ASSINATURA" --topic="$TOPICO" \
    --ack-deadline=60 --message-retention-duration=1d --project="$PROJECT_ID"

echo "== BigQuery"
for arquivo in sql/stream/40_tabelas_stream.sql sql/stream/41_vw_transactions_unified.sql; do
  echo "  $arquivo"
  sed "s/\${PROJECT_ID}/${PROJECT_ID}/g" "$arquivo" |
    bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --quiet
done

echo "== Conta de serviço do Dataflow"
gcloud iam service-accounts describe "$CONTA" --project="$PROJECT_ID" >/dev/null 2>&1 ||
  gcloud iam service-accounts create fraudflow-dataflow --display-name="FraudFlow Dataflow" \
    --project="$PROJECT_ID"
# Executar como worker do Dataflow e gravar no BigQuery.
for papel in roles/dataflow.worker roles/bigquery.dataEditor; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${CONTA}" --role="$papel" --condition=None --quiet >/dev/null
done
# Ler só a própria assinatura.
for papel in roles/pubsub.subscriber roles/pubsub.viewer; do
  gcloud pubsub subscriptions add-iam-policy-binding "$ASSINATURA" \
    --member="serviceAccount:${CONTA}" --role="$papel" --project="$PROJECT_ID" --quiet >/dev/null
done
# Arquivos temporários e de staging do job, no bucket do projeto.
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="serviceAccount:${CONTA}" --role=roles/storage.objectAdmin --quiet >/dev/null

echo
echo "Pronto: tópico ${TOPICO}, assinatura ${ASSINATURA}, tabelas e view, conta ${CONTA}"
