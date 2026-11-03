#!/usr/bin/env bash
# Baixa a exportação do modelo para api/modelo/, de onde o Dockerfile a copia.
# Grava em api/modelo/VERSAO a versão do Registry e a origem do artefato.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
REGION="${REGION:-us-central1}"
EXPORT_URI="${EXPORT_URI:-gs://fraudflow-pdm-gps-data/models/fraud_boosted/20261102_221500}"
DESTINO="$(cd "$(dirname "$0")/.." && pwd)/modelo"

rm -rf "$DESTINO"
mkdir -p "$DESTINO"

# A exportação do BigQuery cria objetos vazios que representam pastas (nomes
# terminados em /). Só os arquivos de verdade são copiados.
gcloud storage ls "$EXPORT_URI/**" | grep -v '/$' | while read -r uri; do
  relativo="${uri#"$EXPORT_URI"/}"
  mkdir -p "$DESTINO/$(dirname "$relativo")"
  gcloud storage cp --quiet "$uri" "$DESTINO/$relativo"
done

VERSAO=$(gcloud ai models describe fraudflow-boosted \
  --project="$PROJECT_ID" --region="$REGION" --format='value(versionId)')
echo "fraudflow-boosted v${VERSAO} · ${EXPORT_URI}" > "$DESTINO/VERSAO"

echo
echo "Modelo em $DESTINO:"
find "$DESTINO" -type f | sed "s|$DESTINO/|  |" | sort
echo "  VERSAO: $(cat "$DESTINO/VERSAO")"
