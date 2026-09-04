#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Parte 1 - Passo B: baixar o dataset Sparkov do Kaggle
#
# Baixa e descompacta fraudTrain.csv e fraudTest.csv em ${DATA_DIR}.
#
# PRE-REQUISITO: token do Kaggle. O formato atual e um token unico "KGAT_...",
# obtido em kaggle.com -> Settings -> API -> "Generate New Token". Ele pode ser
# fornecido de tres formas (a CLI aceita qualquer uma):
#
#   a) variavel de ambiente:  export KAGGLE_API_TOKEN="KGAT_..."
#   b) arquivo:               ~/.kaggle/access_token  (so o token, sem aspas)
#   c) legado:                ~/.kaggle/kaggle.json   (ainda funciona)
#
# OBS: se voce estiver usando os notebooks em Notebooks/, este script nao e
# necessario — o 00_setup_e_ingestao.ipynb ja faz o download pedindo o token
# com getpass, sem gravar nada em disco.
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

if [[ -n "${KAGGLE_API_TOKEN:-}" ]]; then
  echo "    autenticando por KAGGLE_API_TOKEN"
elif [[ -f "${HOME}/.kaggle/access_token" ]]; then
  chmod 600 "${HOME}/.kaggle/access_token"
  echo "    autenticando por ~/.kaggle/access_token"
elif [[ -f "${HOME}/.kaggle/kaggle.json" ]]; then
  chmod 600 "${HOME}/.kaggle/kaggle.json"
  echo "    autenticando por ~/.kaggle/kaggle.json (formato legado)"
else
  echo "ERRO: nenhuma credencial do Kaggle encontrada." >&2
  echo "      Veja as tres opcoes no cabecalho deste script." >&2
  exit 1
fi

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
