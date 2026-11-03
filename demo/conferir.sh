#!/usr/bin/env bash
# Confere, de ponta a ponta, se o streaming está processando agora:
#   gerador publicando → job do Dataflow em execução → linhas novas no BigQuery
# e se a API principal responde.
#
# Uso, da raiz do repositório: bash demo/conferir.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source demo/comum.sh

echo "== Gerador (últimas linhas de ~/gerador.log)"
if pgrep -f producer/publisher.py >/dev/null; then echo "  rodando"; else echo "  PARADO"; fi
tail -n 2 ~/gerador.log 2>/dev/null | sed 's/^/  /'

echo "== Dataflow"
JOB=$(job_ativo)
if [[ -n "$JOB" ]]; then
  echo "  $JOB: $(estado_do_job "$JOB")"
else
  echo "  nenhum job ativo"
fi

echo "== BigQuery: chegadas nos últimos 5 minutos"
bq --project_id="$PROJECT_ID" --location="$REGION" query --use_legacy_sql=false --quiet --format=pretty "
  SELECT
    (SELECT COUNT(*) FROM \`${PROJECT_ID}.silver.transactions_stream\`
     WHERE processed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)) AS validas_5min,
    (SELECT COUNT(*) FROM \`${PROJECT_ID}.silver.transactions_stream_errors\`
     WHERE processed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)) AS erros_5min,
    (SELECT MAX(processed_at) FROM \`${PROJECT_ID}.silver.transactions_stream\`) AS ultima_chegada"

echo "== API principal"
curl -s -o /dev/null -w "  /health → %{http_code} em %{time_total}s\n" --max-time 120 \
  "$(url_do_servico fraudflow-api)/health"
