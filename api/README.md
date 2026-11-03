# API de pontuação

FastAPI com o modelo `fraud_boosted` carregado no próprio container: o
`TRANSFORM` exportado como TensorFlow SavedModel e o XGBoost, encadeados pelo
`Predictor` da biblioteca `bigquery-ml-utils`.

| Rota | O que faz |
|---|---|
| `GET /health` | Responde depois que o modelo carregou; informa a versão |
| `POST /v1/score` | Recebe os nove campos de uma transação e devolve o `fraud_score` |
| `GET /docs` | Contrato interativo, gerado pelo FastAPI |

## Teste de paridade no Cloud Shell

Antes de publicar, a imagem precisa reproduzir o `ML.PREDICT` do BigQuery para
as mesmas transações. Na pasta `api/`:

```bash
bash scripts/baixar_modelo.sh       # exportação do modelo → api/modelo/
bash scripts/gerar_amostra.sh       # 50 transações + score do ML.PREDICT → api/teste/
docker build -t fraudflow-api:local .
docker run --rm \
  -v "$PWD/scripts:/app/scripts:ro" -v "$PWD/teste:/teste:ro" \
  fraudflow-api:local python scripts/paridade.py /teste/amostra.json
```

O teste só aprova se todas as verificações passarem: 50 transações, scores
finitos e diferença máxima abaixo de `1e-4`.

## Teste local por HTTP

```bash
docker run -d --rm -p 8080:8080 --name fraudflow-api fraudflow-api:local
curl -s localhost:8080/health
curl -s -X POST localhost:8080/v1/score -H 'Content-Type: application/json' -d '{
  "transaction_ts": "2020-06-21 02:14:25", "customer_dob": "1968-03-19",
  "customer_lat": 33.97, "customer_long": -80.94,
  "merchant_lat": 33.99, "merchant_long": -81.20,
  "amount": 965.05, "category": "shopping_net", "city_pop": 333497
}'
docker stop fraudflow-api
```
