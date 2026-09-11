# FraudFlow

Detecção de fraude em transações de cartão na Google Cloud.
Disciplina de **Processamento de Dados Massivos** — projeto em três entregas.

| Entrega | Escopo | Apresentação |
|---|---|---|
| Trabalho 1 | Arquitetura Medallion no BigQuery + modelo em BigQuery ML | 11/09/2026 |
| Trabalho 2 | Streaming Pub/Sub + Dataflow, deploy no Vertex AI, API no Cloud Run | 23/10/2026 |
| Trabalho Final | Dataflow chamando a API em tempo real + orquestração | 04/12/2026 |

## Dataset

[Credit Card Transactions Fraud Detection](https://www.kaggle.com/datasets/kartik2112/fraud-detection),
gerado pelo simulador Sparkov: 1.852.394 transações entre 2019 e 2020, com 9.651
fraudes (0,52%).

O dataset já vem dividido em dois arquivos, e a divisão é **temporal**:
`fraudTrain.csv` vai até 21/06/2020 e `fraudTest.csv` cobre o período seguinte.

- **`fraudTrain.csv`** — usado no Trabalho 1. A validação sai de um recorte
  temporal dentro dele, com `DATA_SPLIT_METHOD='SEQ'`.
- **`fraudTest.csv`** — não é carregado no BigQuery. Permanece em
  `gs://BUCKET/holdout/` e será reproduzido como stream no Trabalho 2, quando o
  modelo passa a classificar um período que não viu durante o desenvolvimento.

### Armadilha do dataset

As duas colunas de tempo **discordam em exatamente sete anos-calendário**:
`trans_date_trans_time` indica 2019–2020 e `unix_time`, na mesma linha, indica
2012–2013. A camada Silver adota `trans_date_trans_time` como fonte única e
descarta `unix_time` — calcular idade pela coluna errada deixaria todo cliente
sete anos mais novo, sem gerar nenhum erro.

## Arquitetura do Trabalho 1

```
Kaggle
   |
   v
Cloud Storage   raw/train/   +   holdout/  (não carregado)
   |
   v
BRONZE   tabela gerenciada, dados como STRING + metadados de ingestão
   |
   v
SILVER   tipagem, limpeza, deduplicação, resolução do timestamp,
         campos canônicos. Particionada por data da transação.
   |
   +--> GOLD ml_input          contrato do modelo
   |
   +--> GOLD fraud_analytics   agregações para BI
            |
            v
      BigQuery ML   LOGISTIC_REG (v1) e BOOSTED_TREE_CLASSIFIER (v2),
                    com as features na cláusula TRANSFORM
```

**Fronteira entre as camadas:** a Silver entrega *campos canônicos*; a cláusula
`TRANSFORM` entrega *features do modelo*. Nenhuma fórmula é implementada nos dois
lugares, e a transformação viaja junto com o modelo até o Vertex AI.

## Resultados

Avaliados sobre os 20% finais por tempo, que o modelo não viu no treino:

| Modelo | Recall | Precision | F1 | ROC AUC |
|---|---|---|---|---|
| v1 · regressão logística | 0,867 | 0,041 | 0,079 | 0,949 |
| v2 · boosted tree | **0,969** | **0,298** | **0,456** | **0,999** |

O v2 captura 97 de cada 100 fraudes, marcando 1,36% das transações legítimas
para revisão.

Acurácia não é usada como métrica: responder "não é fraude" para tudo daria
99,41%, mais que os 98,63% do modelo. Como os dados vêm de um simulador, as
separações entre classes são mais limpas do que em fraude real — a madrugada
concentra 18× mais fraude, e o modelo elegeu `is_night` como a feature mais
decisiva.

## Estrutura

```
Notebooks/   pipeline completo, na ordem 00 a 04
sql/         mesmos comandos SQL como arquivos avulsos: bronze/ silver/ gold/ ml/
```

## Como executar

Os notebooks rodam no Google Colab. Ajuste `PROJECT_ID` e `BUCKET_NAME` na célula
de parâmetros do notebook 00 e execute na ordem:

| Notebook | O que faz |
|---|---|
| `00_setup_e_ingestao` | Cria bucket e datasets, baixa o dataset do Kaggle e sobe para o GCS |
| `01_raw_to_bronze` | Carrega o CSV do GCS para a camada Bronze |
| `02_bronze_to_silver` | Tipagem, limpeza, deduplicação e campos canônicos |
| `03_silver_to_gold` | Gera `ml_input` e `fraud_analytics` |
| `04_model_and_predict` | Treina, avalia e aplica os dois modelos |

Pré-requisitos: um projeto na Google Cloud com faturamento ativo, as APIs do
BigQuery e do Cloud Storage habilitadas, e um token de API do Kaggle.

Os scripts em `sql/` contêm os mesmos comandos, sem o Python em volta, para
execução direta no console do BigQuery. Substitua `${PROJECT_ID}` pelo id do
projeto antes de rodar.

## Custos

Carga em lote no BigQuery é gratuita, e as consultas têm 1 TiB por mês sem
cobrança. O único custo previsível do Trabalho 1 é o treino: `CREATE MODEL` de
regressão logística é cobrado a US$ 312,50/TiB e não entra na cota gratuita — com
cerca de 100 MB de dados, aproximadamente US$ 0,03 por treino. O
`BOOSTED_TREE_CLASSIFIER` tem ainda um componente de treino cobrado à parte.

Nenhum recurso do Trabalho 1 permanece ligado cobrando por hora.
