#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Parte 1 - Passo B: baixar o dataset Sparkov do Kaggle
#
# Baixa e descompacta fraudTrain.csv e fraudTest.csv em ${DATA_DIR}.
#
# PRE-REQUISITO: credencial do Kaggle em ~/.kaggle/kaggle.json
#   1. kaggle.com -> Settings -> API -> "Create New Token"
#   2. o navegador baixa kaggle.json
#   3. no Cloud Shell:  mkdir -p ~/.kaggle && mv kaggle.json ~/.kaggle/
#      e depois:        chmod 600 ~/.kaggle/kaggle.json
#
# Uso:  bash scripts/01_download_dataset.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

mkdir -p "${DATA_DIR}"

echo
echo "==> 1/3  Verificando a CLI do Kaggle"
if ! command -v kaggle >/dev/null 2>&1; then
  echo "    instalando kaggle..."
  pip install --quiet --user kaggle
  export PATH="${PATH}:${HOME}/.local/bin"
fi

if [[ ! -f "${HOME}/.kaggle/kaggle.json" ]]; then
  echo "ERRO: ~/.kaggle/kaggle.json nao encontrado." >&2
  echo "      Veja as instrucoes no cabecalho deste script." >&2
  exit 1
fi
chmod 600 "${HOME}/.kaggle/kaggle.json"

echo
echo "==> 2/3  Baixando ${KAGGLE_DATASET} (~200 MB compactado)"
if [[ -f "${DATA_DIR}/fraudTrain.csv" && -f "${DATA_DIR}/fraudTest.csv" ]]; then
  echo "    CSVs ja existem, pulando o download."
else
  kaggle datasets download -d "${KAGGLE_DATASET}" -p "${DATA_DIR}" --unzip
fi

echo
echo "==> 3/3  Conferindo os arquivos"
for f in fraudTrain.csv fraudTest.csv; do
  if [[ ! -f "${DATA_DIR}/${f}" ]]; then
    echo "ERRO: ${DATA_DIR}/${f} nao foi encontrado apos o download." >&2
    exit 1
  fi
  size=$(du -h "${DATA_DIR}/${f}" | cut -f1)
  echo "    ${f}  (${size})"
done

echo
echo "OK. Dataset baixado."
echo "Proximo passo: bash scripts/02_upload_to_gcs.sh"
