# Funções usadas pelos scripts de demo/. Carregar com: source demo/comum.sh

PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
REGION="${REGION:-us-central1}"

# Id do job fraudflow-stream ativo (em execução, drenando ou cancelando), ou vazio.
job_ativo() {
  gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION" \
    --status=active --filter='name=fraudflow-stream' --format='value(id)' | head -1
}

estado_do_job() {
  gcloud dataflow jobs describe "$1" --project="$PROJECT_ID" --region="$REGION" \
    --format='value(currentState)'
}

# esperar_estado JOB ESTADO1 [ESTADO2...]: espera até 15 min o job chegar a um
# dos estados. Termina com erro se não chegar.
esperar_estado() {
  local job="$1"; shift
  local estado=""
  for _ in $(seq 1 45); do
    estado=$(estado_do_job "$job")
    for alvo in "$@"; do
      if [[ "$estado" == "$alvo" ]]; then
        echo "  $job: $estado"
        return 0
      fi
    done
    echo "  $job: $estado, aguardando $*..."
    sleep 20
  done
  echo "  $job não chegou a $* em 15 min (último estado: $estado)"
  return 1
}

url_do_servico() {
  gcloud run services describe "$1" --project="$PROJECT_ID" --region="$REGION" \
    --format='value(status.url)'
}
