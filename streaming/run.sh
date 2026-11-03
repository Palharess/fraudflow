#!/usr/bin/env bash
# Executa o pipeline de streaming.
#
#   bash run.sh local      DirectRunner no Cloud Shell, para testar (Ctrl+C para parar)
#   bash run.sh dataflow   envia ao Dataflow; o job continua depois que o terminal fecha
#
# Pré-requisito: bash infra/setup_streaming.sh (tópico, assinatura, tabelas, conta).
# Para parar o job do Dataflow: bash infra/teardown.sh
set -euo pipefail
cd "$(dirname "$0")"

MODO="${1:-dataflow}"
PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
REGION="${REGION:-us-central1}"
BUCKET="${BUCKET:-gs://fraudflow-pdm-gps-data}"
MAQUINA="${MAQUINA:-n1-standard-2}"

COMUNS=(
  --subscription="projects/${PROJECT_ID}/subscriptions/transactions-dataflow"
  --tabela="${PROJECT_ID}:silver.transactions_stream"
  --tabela_erros="${PROJECT_ID}:silver.transactions_stream_errors"
  --project="$PROJECT_ID"
)

case "$MODO" in
  local)
    # O executor clássico do DirectRunner: é ele que implementa a leitura do
    # Pub/Sub em streaming. Sem o nome explícito, o DirectRunner pode tentar
    # outro executor primeiro.
    python pipeline.py "${COMUNS[@]}" --runner=BundleBasedDirectRunner
    ;;
  dataflow)
    # Um worker fixo: o volume da demonstração cabe nele, e o custo fica
    # previsível. O nome fixo impede dois jobs iguais rodando ao mesmo tempo.
    python pipeline.py "${COMUNS[@]}" \
      --runner=DataflowRunner \
      --region="$REGION" \
      --job_name=fraudflow-stream \
      --service_account_email="fraudflow-dataflow@${PROJECT_ID}.iam.gserviceaccount.com" \
      --temp_location="${BUCKET}/dataflow/temp" \
      --staging_location="${BUCKET}/dataflow/staging" \
      --setup_file=./setup.py \
      --enable_streaming_engine \
      --worker_machine_type="$MAQUINA" \
      --num_workers=1 --max_num_workers=1
    echo
    echo "Job enviado. Acompanhe em: https://console.cloud.google.com/dataflow/jobs?project=${PROJECT_ID}"
    ;;
  *)
    echo "Uso: bash run.sh local|dataflow"; exit 1 ;;
esac
