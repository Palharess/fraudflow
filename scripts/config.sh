#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# FraudFlow - configuracao central
#
# Este arquivo e a UNICA fonte de configuracao. Todos os outros scripts fazem
# "source config.sh". Ajuste PROJECT_ID e rode os demais scripts na ordem.
#
# Uso:  source scripts/config.sh
# ---------------------------------------------------------------------------

# --- AJUSTE AQUI -----------------------------------------------------------
# ID do projeto GCP (precisa ser unico globalmente).
# Sugestao: fraudflow-pdm-<suas-iniciais>
export PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
# ---------------------------------------------------------------------------

# Regiao unica para TODOS os servicos do projeto (decisao D1 do plano).
# us-central1: disponibilidade total de BigQuery ML, Vertex AI e Dataflow,
# que serao usados nos Trabalhos 2 e Final. Bucket e dataset ficam colocados
# na mesma regiao para evitar erro de cross-region na carga.
export REGION="us-central1"
export BQ_LOCATION="us-central1"

# Bucket de dados (nome precisa ser unico globalmente).
export BUCKET_NAME="${PROJECT_ID}-data"
export BUCKET="gs://${BUCKET_NAME}"

# Caminhos no bucket.
#   raw/train/    -> fraudTrain.csv, usado no Trabalho 1
#   holdout/      -> fraudTest.csv, LACRADO ate o Trabalho 2
export GCS_RAW_TRAIN="${BUCKET}/raw/train"
export GCS_HOLDOUT="${BUCKET}/holdout"

# Datasets do BigQuery (criados na Parte 2).
export BQ_BRONZE="bronze"
export BQ_SILVER="silver"
export BQ_GOLD="gold"
export BQ_ML="ml"

# Dataset de origem no Kaggle.
export KAGGLE_DATASET="kartik2112/fraud-detection"

# Contagens esperadas - usadas para validar a ingestao (linhas de DADOS,
# sem contar o cabecalho).
export EXPECTED_TRAIN_ROWS=1296675
export EXPECTED_TEST_ROWS=555719

# Diretorio local de trabalho (ignorado pelo git).
export DATA_DIR="${DATA_DIR:-./data}"

if [[ "${PROJECT_ID}" == "AJUSTE-ME" ]]; then
  echo "ERRO: edite scripts/config.sh e defina PROJECT_ID." >&2
  return 1 2>/dev/null || exit 1
fi

echo "FraudFlow | projeto=${PROJECT_ID} | regiao=${REGION} | bucket=${BUCKET}"
