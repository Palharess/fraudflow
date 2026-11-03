#!/usr/bin/env bash
# Prepara a demonstração ao vivo. Rodar ~60 minutos antes da apresentação.
#
#   1. sobe o job de streaming no Dataflow, se ainda não estiver rodando
#   2. deixa uma instância sempre ligada na API principal (sem partida a frio)
#   3. confere a saúde das duas APIs
#
# Uso, da raiz do repositório, com o ambiente do Beam ativo:
#   source ~/venv-beam/bin/activate && bash demo/preparar.sh
#
# Depois da apresentação: bash infra/teardown.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
REGION="${REGION:-us-central1}"

python -c "import apache_beam" 2>/dev/null ||
  { echo "Ative antes o ambiente do Beam: source ~/venv-beam/bin/activate"; exit 1; }

echo "== Dataflow"
ATIVO=$(gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION" \
  --status=active --filter='name=fraudflow-stream' --format='value(id)')
if [[ -n "$ATIVO" ]]; then
  echo "  já em execução: $ATIVO"
else
  bash streaming/run.sh dataflow
fi

echo "== Cloud Run: uma instância sempre ligada na API principal"
# Custa enquanto estiver ligada; o teardown volta para zero.
gcloud run services update fraudflow-api --project="$PROJECT_ID" --region="$REGION" \
  --min-instances=1 --quiet >/dev/null 2>&1
echo "  fraudflow-api: instância mínima = 1"

echo "== Saúde das APIs"
for servico in fraudflow-api fraudflow-api-bq; do
  URL=$(gcloud run services describe "$servico" --project="$PROJECT_ID" --region="$REGION" \
    --format='value(status.url)')
  curl -s -o /dev/null -w "  $servico  /health → %{http_code} em %{time_total}s\n" "$URL/health"
done

echo
echo "Próximos passos:"
echo "  1. Console → Dataflow → fraudflow-stream: espere 'Em execução' com 1 worker."
echo "     Se em 15 min não aparecer worker: bash infra/teardown.sh e"
echo "     MAQUINA=e2-standard-2 bash demo/preparar.sh"
echo "  2. Ligue o gerador em segundo plano (veja demo/README.md)."
