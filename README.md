# FraudFlow

Detecção de fraudes em transações de cartão na Google Cloud.
Disciplina de **Processamento de Dados Massivos** — projeto em três entregas.

| Entrega | Escopo | Apresentação |
|---|---|---|
| Trabalho 1 | Arquitetura Medallion no BigQuery + modelo em BigQuery ML | 11/09/2026 |
| Trabalho 2 | Streaming Pub/Sub + Dataflow, deploy no Vertex AI, API no Cloud Run | 23/10/2026 |
| Trabalho Final | Dataflow chamando a API em tempo real + orquestração com n8n | 04/12/2026 |

## Dataset

[Credit Card Transactions Fraud Detection](https://www.kaggle.com/datasets/kartik2112/fraud-detection)
(gerador Sparkov), 1.852.394 transações entre 2019 e 2020, com 9.651 fraudes (0,52%).

O split do dataset é **temporal**: `fraudTrain.csv` vai até cerca de 21/06/2020 e
`fraudTest.csv` cobre o período seguinte. Por isso:

- **`fraudTrain.csv`** — usado no Trabalho 1 (treino e validação).
- **`fraudTest.csv`** — **holdout lacrado**. Não entra no BigQuery no Trabalho 1.
  No Trabalho 2 ele é reproduzido como stream, e o modelo passa a classificar
  transações de um período que nunca viu durante o desenvolvimento.

### Armadilha conhecida do dataset

As duas colunas de tempo **discordam em exatos 7 anos**: `trans_date_trans_time`
indica 2019–2020 e `unix_time`, na mesma linha, indica 2012–2013.
A camada Silver adota **`trans_date_trans_time` como fonte única da verdade**;
`unix_time` é descartado. Misturar as duas produz idades erradas em 7 anos,
sem gerar nenhum erro.

## Arquitetura do Trabalho 1

```
Kaggle
   |
   v
Cloud Storage  raw/train/  +  holdout/  (lacrado)
   |
   v
BRONZE   tabela gerenciada, dados crus + metadados de ingestão
   |
   v
SILVER   tipagem, limpeza, deduplicação, resolução do timestamp,
         campos canônicos. Particionada por data da transação.
   |
   +--> GOLD ml_input          campos prontos para o modelo
   |
   +--> GOLD fraud_analytics   agregações para BI
            |
            v
      BigQuery ML   LOGISTIC_REG (v1) e BOOSTED_TREE_CLASSIFIER (v2)
                    features derivadas dentro da cláusula TRANSFORM
```

**Fronteira entre as camadas:** a Silver entrega *campos canônicos*; a cláusula
`TRANSFORM` entrega *features do modelo*. Nenhuma fórmula é implementada nos
dois lugares — assim existe uma única fonte da verdade, e a transformação viaja
junto com o modelo até o endpoint do Vertex AI no Trabalho 2.

## Estrutura

```
scripts/    configuração e ingestão (bash)
sql/        bronze/ silver/ gold/ ml/
docs/       diagramas e dicionário de dados
data/       CSVs locais (ignorado pelo git)
```

## Como executar

Recomendado rodar no **Cloud Shell** — já traz `gcloud`, `bq` e `python`
instalados, e o download do Kaggle usa a rede do Google.

```bash
# 1. ajuste o PROJECT_ID
nano scripts/config.sh

# 2. fundação: projeto, APIs e bucket
bash scripts/00_setup_gcp.sh

# 3. baixar o dataset do Kaggle
bash scripts/01_download_dataset.sh

# 4. ingestão da camada raw no Cloud Storage
bash scripts/02_upload_to_gcs.sh
```

## Custos

Carga em lote no BigQuery é gratuita, e as consultas têm 1 TiB por mês sem
cobrança. O único custo previsível do Trabalho 1 é o treino do modelo:
`CREATE MODEL` de regressão logística é cobrado a US$ 312,50/TiB e **não entra
no free tier** — com cerca de 100 MB de dados isso dá aproximadamente US$ 0,03
por treino. O `BOOSTED_TREE_CLASSIFIER` tem custo de processamento no BigQuery
mais um componente de treino no Vertex AI, que deve ser conferido no Billing
após a primeira execução.

Nenhum recurso do Trabalho 1 fica ligado cobrando por hora.
