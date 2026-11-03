#!/usr/bin/env bash
# Desliga o que cobra por hora, do mais caro para o mais barato.
#
#   1. job de streaming no Dataflow (drain: termina o que já leu e para)
#   2. endpoint do Vertex AI, se existir
#   3. instância mínima do Cloud Run, se alguém deixou ligada
#
# Não apaga dados, tabelas, tópico, imagens nem os serviços do Cloud Run:
# parados, eles não cobram por hora.
#
# Uso: bash infra/teardown.sh
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
REGION="${REGION:-us-central1}"

echo "== Dataflow"
JOBS=$(gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION" \
  --status=active --format='value(id)')
if [[ -z "$JOBS" ]]; then
  echo "  nenhum job ativo"
else
  for job in $JOBS; do
    gcloud dataflow jobs drain "$job" --project="$PROJECT_ID" --region="$REGION"
    echo "  drain pedido: $job (leva alguns minutos para terminar)"
  done
fi

echo "== Vertex AI"
ENDPOINTS=$(gcloud ai endpoints list --project="$PROJECT_ID" --region="$REGION" \
  --filter='displayName=fraudflow-endpoint' --format='value(name)' 2>/dev/null || true)
if [[ -z "$ENDPOINTS" ]]; then
  echo "  nenhum endpoint"
else
  for endpoint in $ENDPOINTS; do
    for implantado in $(gcloud ai endpoints describe "$endpoint" --project="$PROJECT_ID" \
        --region="$REGION" --format='value(deployedModels.id)' | tr ';' ' '); do
      gcloud ai endpoints undeploy-model "$endpoint" --deployed-model-id="$implantado" \
        --project="$PROJECT_ID" --region="$REGION" --quiet
    done
    gcloud ai endpoints delete "$endpoint" --project="$PROJECT_ID" --region="$REGION" --quiet
    echo "  apagado: $endpoint"
  done
fi

echo "== Cloud Run"
for servico in fraudflow-api fraudflow-api-bq; do
  # Só atualiza se houver instância mínima: cada update cria uma revisão nova.
  minimo=$(gcloud run services describe "$servico" --project="$PROJECT_ID" --region="$REGION" \
    --format='value(spec.template.metadata.annotations."autoscaling.knative.dev/minScale")' 2>/dev/null || true)
  if [[ -n "$minimo" && "$minimo" != "0" ]]; then
    gcloud run services update "$servico" --min-instances=0 \
      --project="$PROJECT_ID" --region="$REGION" --quiet >/dev/null 2>&1
    echo "  $servico: instância mínima desligada (era $minimo)"
  else
    echo "  $servico: já sem instância mínima"
  fi
done

echo
echo "Confira os jobs em https://console.cloud.google.com/dataflow/jobs?project=${PROJECT_ID}"
