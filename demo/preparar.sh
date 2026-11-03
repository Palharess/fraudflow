#!/usr/bin/env bash
# Prepara a demonstração ao vivo. Rodar ~60 minutos antes da apresentação.
#
#   1. API principal com uma instância sempre ligada (sem partida a frio)
#   2. saúde das duas APIs e uma requisição de aquecimento
#   3. job de streaming no Dataflow: sobe, se ainda não existir, e espera ficar
#      em execução
#
# Depois de ligar o gerador, conferir o processamento com: bash demo/conferir.sh
#
# Uso, da raiz do repositório, com o ambiente do Beam ativo:
#   source ~/venv-beam/bin/activate && bash demo/preparar.sh
#
# Depois da apresentação: bash infra/teardown.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source demo/comum.sh

python -c "import apache_beam" 2>/dev/null ||
  { echo "Ative antes o ambiente do Beam: source ~/venv-beam/bin/activate"; exit 1; }

echo "== 1. API principal: uma instância sempre ligada"
# Custa enquanto estiver ligada; o teardown volta para zero.
gcloud run services update fraudflow-api --project="$PROJECT_ID" --region="$REGION" \
  --min-instances=1 --quiet >/dev/null 2>&1
echo "  fraudflow-api: instância mínima = 1"

echo "== 2. Saúde e aquecimento das APIs"
for servico in fraudflow-api fraudflow-api-bq; do
  curl -s -o /dev/null -w "  $servico  /health → %{http_code} em %{time_total}s\n" \
    --max-time 120 "$(url_do_servico "$servico")/health"
done
if python3 demo/testar_api.py >/dev/null; then
  echo "  requisição de aquecimento na API principal: ok"
else
  echo "  AVISO: aquecimento falhou; rode python3 demo/testar_api.py e veja o erro"
fi

echo "== 3. Dataflow"
JOB=$(job_ativo)
if [[ -n "$JOB" ]]; then
  echo "  já existe um job ativo: $JOB"
else
  bash streaming/run.sh dataflow
  JOB=$(job_ativo)
fi
esperar_estado "$JOB" JOB_STATE_RUNNING

echo
echo "Próximos passos:"
echo "  1. Console → Dataflow → fraudflow-stream: o job em execução ainda precisa de 1 worker."
echo "     Sem worker em 15 min: MAQUINA=e2-standard-2 bash demo/reiniciar_dataflow.sh"
echo "  2. Ligar o gerador em segundo plano (demo/README.md) e, 2 minutos depois:"
echo "     bash demo/conferir.sh"
