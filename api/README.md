# API de pontuação

FastAPI no Cloud Run. Recebe os nove campos de uma transação e devolve o
`fraud_score` do modelo `fraud_boosted`. O mesmo código roda com dois backends:

| Serviço | Backend | Como pontua | Papel |
|---|---|---|---|
| `fraudflow-api` | `local` | modelo exportado dentro do container: `TRANSFORM` (TensorFlow SavedModel) → XGBoost | principal |
| `fraudflow-api-bq` | `bigquery` | `ML.PREDICT` no BigQuery, sem TensorFlow | contingência |

| Rota | O que faz |
|---|---|
| `GET /health` | Responde depois que o modelo carregou; informa backend e versão |
| `POST /v1/score` | Recebe os nove campos e devolve o `fraud_score` (422 se a entrada for inválida) |
| `GET /docs` | Contrato interativo, gerado pelo FastAPI |

A entrada segue as regras da Silver: valor positivo, coordenadas válidas, uma
das 14 categorias conhecidas e nascimento anterior à compra. Horário sem fuso
é lido como UTC.

## Arquivos

```
app/main.py            rotas e escolha do backend (variável BACKEND)
app/schemas.py         contrato de entrada e saída
app/modelo.py          ModeloLocal e ModeloBigQuery
Dockerfile             imagem principal (Python 3.11, TensorFlow, modelo)
Dockerfile.bigquery    imagem de contingência
deploy.sh              publica no Cloud Run: bash deploy.sh local|bigquery
cloudbuild.yaml        build no Cloud Build, usado pelo deploy.sh
scripts/               baixar o modelo, gerar a amostra e os testes de paridade
```

## 1. Paridade dentro da imagem

O container precisa reproduzir o BigQuery: as mesmas features do
`ML.TRANSFORM` e o mesmo score do `ML.PREDICT`, nas mesmas 50 transações. No
Cloud Shell, na pasta `api/`:

```bash
bash scripts/baixar_modelo.sh       # exportação do modelo → api/modelo/
bash scripts/gerar_amostra.sh       # 50 transações + referência do BigQuery → api/teste/
docker build -t fraudflow-api:local .
docker run --rm \
  -v "$PWD/scripts:/app/scripts:ro" -v "$PWD/teste:/teste:ro" \
  fraudflow-api:local python scripts/paridade.py /teste/amostra.json
```

Resultado em 03/11/2026: as nove features iguais, diferença de score 0 e
inferência de 2,4 ms por transação.

## 2. Publicação

```bash
IMAGEM_LOCAL=fraudflow-api:local bash deploy.sh local   # publica a imagem testada acima
bash deploy.sh bigquery                                 # contingência, build no Cloud Build
```

Cada serviço tem conta de serviço própria. A principal não recebe papel
nenhum; a contingência recebe só `bigquery.jobUser` e `bigquery.dataViewer`.

## 3. Paridade por HTTP

Com o serviço publicado, a mesma amostra passa pela API inteira:

```bash
python3 scripts/paridade_http.py "$(gcloud run services describe fraudflow-api --region us-central1 --format='value(status.url)')" teste/amostra.json
```

Confere as 50 respostas contra o `ML.PREDICT`, o erro 422 para entrada
inválida e mede a latência de ponta a ponta.
