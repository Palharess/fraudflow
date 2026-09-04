#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Parte 1 - Passo A: fundacao do projeto na GCP
#
# Cria/configura o projeto, habilita as APIs necessarias e cria o bucket
# de dados. Idempotente: pode rodar de novo sem quebrar.
#
# Uso:  bash scripts/00_setup_gcp.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo
echo "==> 1/4  Definindo o projeto ativo"
gcloud config set project "${PROJECT_ID}"

echo
echo "==> 2/4  Habilitando APIs (gratuito; leva ~1 min na primeira vez)"
# Apenas o necessario para o Trabalho 1. As APIs de Pub/Sub, Dataflow,
# Cloud Run e Vertex AI serao habilitadas no Trabalho 2.
gcloud services enable \
  bigquery.googleapis.com \
  storage.googleapis.com

echo
echo "==> 3/4  Criando o bucket ${BUCKET}"
if gcloud storage buckets describe "${BUCKET}" >/dev/null 2>&1; then
  echo "    bucket ja existe, seguindo."
else
  # --uniform-bucket-level-access: permissoes so por IAM, sem ACL por objeto.
  # E a recomendacao atual do Google e simplifica o acesso do BigQuery.
  gcloud storage buckets create "${BUCKET}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
  echo "    bucket criado."
fi

echo
echo "==> 4/4  Verificando"
gcloud storage buckets describe "${BUCKET}" \
  --format="value(name,location,storageClass)"

echo
echo "OK. Fundacao pronta."
echo "Proximo passo: bash scripts/01_download_dataset.sh"
