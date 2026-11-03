#!/usr/bin/env bash
# Plano B: o job não conseguiu worker. Cancela o job atual, espera ele encerrar
# de verdade e sobe outro, com outro tipo de máquina.
#
#   MAQUINA=e2-standard-2 bash demo/reiniciar_dataflow.sh
#
# Cancelar, e não drenar: um job sem worker não tem o que drenar, e o drain
# pode demorar. As mensagens que ele não confirmou continuam na assinatura e são
# lidas pelo job novo.
set -euo pipefail
cd "$(dirname "$0")/.."
source demo/comum.sh

python -c "import apache_beam" 2>/dev/null ||
  { echo "Ative antes o ambiente do Beam: source ~/venv-beam/bin/activate"; exit 1; }

JOB=$(job_ativo)
if [[ -n "$JOB" ]]; then
  echo "== Cancelando $JOB"
  gcloud dataflow jobs cancel "$JOB" --project="$PROJECT_ID" --region="$REGION"
  # Só com o job anterior encerrado o novo pode usar o mesmo nome.
  esperar_estado "$JOB" JOB_STATE_CANCELLED JOB_STATE_DRAINED JOB_STATE_FAILED JOB_STATE_DONE
fi

echo "== Novo job com ${MAQUINA:-n1-standard-2}"
bash streaming/run.sh dataflow
esperar_estado "$(job_ativo)" JOB_STATE_RUNNING
echo "Confira o worker no console e depois: bash demo/conferir.sh"
