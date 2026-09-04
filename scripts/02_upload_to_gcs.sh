#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Parte 1 - Passo C: ingestao dos dados brutos no Cloud Storage
#
# Sobe os CSVs para o GCS mantendo a separacao decidida no plano:
#
#   raw/train/fraudTrain.csv  -> usado no Trabalho 1
#   holdout/fraudTest.csv     -> LACRADO. Nao entra no BigQuery no Trabalho 1.
#                                Vira o "futuro nunca visto" no Trabalho 2.
#
# O split do Sparkov e TEMPORAL: o treino vai ate ~21/06/2020 e o teste
# comeca em seguida. Por isso o holdout representa mesmo um periodo futuro.
#
# Uso:  bash scripts/02_upload_to_gcs.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

echo
echo "==> 1/4  Validando as contagens locais (antes de subir)"
# wc -l conta o cabecalho, por isso subtraimos 1 para ter linhas de dados.
check_rows () {
  local file="$1" expected="$2" nome="$3"
  local total data
  total=$(wc -l < "${file}")
  data=$(( total - 1 ))
  printf "    %-16s %10d linhas de dados (esperado %d) " "${nome}" "${data}" "${expected}"
  if [[ "${data}" -eq "${expected}" ]]; then
    echo "OK"
  else
    echo "DIVERGENTE"
    echo "ERRO: contagem inesperada em ${file}." >&2
    echo "      Se o numero for 1048575, o arquivo passou por Excel e esta truncado." >&2
    echo "      Baixe novamente direto do Kaggle." >&2
    exit 1
  fi
}
check_rows "${DATA_DIR}/fraudTrain.csv" "${EXPECTED_TRAIN_ROWS}" "fraudTrain.csv"
check_rows "${DATA_DIR}/fraudTest.csv"  "${EXPECTED_TEST_ROWS}"  "fraudTest.csv"

echo
echo "==> 2/4  Enviando o treino para ${GCS_RAW_TRAIN}/"
gcloud storage cp "${DATA_DIR}/fraudTrain.csv" "${GCS_RAW_TRAIN}/fraudTrain.csv"

echo
echo "==> 3/4  Enviando o holdout para ${GCS_HOLDOUT}/  (lacrado ate o T2)"
gcloud storage cp "${DATA_DIR}/fraudTest.csv" "${GCS_HOLDOUT}/fraudTest.csv"

# Marcador explicito para que ninguem do grupo use o holdout por engano.
cat <<'AVISO' > "${DATA_DIR}/LEIA-ME.txt"
HOLDOUT LACRADO - NAO USAR NO TRABALHO 1

fraudTest.csv representa o periodo POSTERIOR ao treino (a partir de ~jun/2020).
Ele nao deve ser carregado no BigQuery nem usado em ML.PREDICT no Trabalho 1.

Uso previsto: Trabalho 2, reproduzido como stream via Pub/Sub, para o modelo
classificar transacoes de um periodo que nunca viu durante o desenvolvimento.
AVISO
gcloud storage cp "${DATA_DIR}/LEIA-ME.txt" "${GCS_HOLDOUT}/LEIA-ME.txt"

echo
echo "==> 4/4  Conferindo o que ficou no bucket"
gcloud storage ls -l "${BUCKET}/**"

echo
echo "OK. Ingestao concluida."
echo "Camada raw no GCS pronta. Proxima etapa: Bronze no BigQuery (Parte 2)."
