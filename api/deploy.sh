#!/usr/bin/env bash
# Publica a API no Cloud Run.
#
#   bash deploy.sh local       serviço fraudflow-api     modelo no container (principal)
#   bash deploy.sh bigquery    serviço fraudflow-api-bq  ML.PREDICT (contingência)
#
# Por padrão a imagem é construída no Cloud Build. Com IMAGEM_LOCAL definida,
# publica uma imagem já construída no Cloud Shell, como a que passou no teste
# de paridade:
#   IMAGEM_LOCAL=fraudflow-api:local bash deploy.sh local
set -euo pipefail
cd "$(dirname "$0")"

BACKEND="${1:-local}"
PROJECT_ID="${PROJECT_ID:-fraudflow-pdm-gps}"
REGION="${REGION:-us-central1}"
REPOSITORIO="fraudflow"

case "$BACKEND" in
  local)
    SERVICO="fraudflow-api"
    DOCKERFILE="Dockerfile"
    MEMORIA="2Gi"     # TensorFlow + XGBoost carregados
    [[ -f modelo/model.bst ]] || { echo "Falta o modelo: rode antes bash scripts/baixar_modelo.sh"; exit 1; }
    ;;
  bigquery)
    SERVICO="fraudflow-api-bq"
    DOCKERFILE="Dockerfile.bigquery"
    MEMORIA="512Mi"
    ;;
  *)
    echo "Uso: bash deploy.sh local|bigquery"; exit 1 ;;
esac

CONTA="${SERVICO}@${PROJECT_ID}.iam.gserviceaccount.com"
IMAGEM="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORIO}/${SERVICO}:$(date +%Y%m%d-%H%M%S)"

echo "== APIs"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com --project="$PROJECT_ID"

echo "== Repositório de imagens"
gcloud artifacts repositories describe "$REPOSITORIO" --location="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1 ||
  gcloud artifacts repositories create "$REPOSITORIO" --repository-format=docker \
    --location="$REGION" --project="$PROJECT_ID"

echo "== Conta de serviço própria do serviço"
gcloud iam service-accounts describe "$CONTA" --project="$PROJECT_ID" >/dev/null 2>&1 ||
  gcloud iam service-accounts create "$SERVICO" --display-name="FraudFlow ${SERVICO}" \
    --project="$PROJECT_ID"
# Só a contingência acessa o GCP: roda consultas e lê o modelo no BigQuery. A
# principal não recebe papel nenhum, porque o modelo está dentro da imagem.
if [[ "$BACKEND" == "bigquery" ]]; then
  for papel in roles/bigquery.jobUser roles/bigquery.dataViewer; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${CONTA}" --role="$papel" --condition=None --quiet >/dev/null
  done
fi

echo "== Imagem $IMAGEM"
if [[ -n "${IMAGEM_LOCAL:-}" ]]; then
  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
  docker tag "$IMAGEM_LOCAL" "$IMAGEM"
  docker push "$IMAGEM"
else
  gcloud builds submit . --project="$PROJECT_ID" --config=cloudbuild.yaml \
    --substitutions="_DOCKERFILE=${DOCKERFILE},_IMAGEM=${IMAGEM}"
fi

echo "== Cloud Run"
# Sem instância mínima: parado, não cobra. Para o ensaio e a apresentação,
# subir com --min-instances=1 evita a primeira chamada lenta.
gcloud run deploy "$SERVICO" \
  --project="$PROJECT_ID" --region="$REGION" \
  --image="$IMAGEM" \
  --service-account="$CONTA" \
  --set-env-vars="BACKEND=${BACKEND},PROJECT_ID=${PROJECT_ID}" \
  --memory="$MEMORIA" --cpu=1 --cpu-boost \
  --concurrency=8 --min-instances=0 --max-instances=2 \
  --allow-unauthenticated

URL=$(gcloud run services describe "$SERVICO" --project="$PROJECT_ID" \
  --region="$REGION" --format='value(status.url)')
echo
echo "URL: $URL"
curl -s "$URL/health"; echo
