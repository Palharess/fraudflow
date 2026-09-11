# Scripts SQL — Arquitetura Medallion

Ordem de execução. Todos os arquivos usam `${PROJECT_ID}` como placeholder:
substitua pelo id do projeto antes de executar.

| # | Arquivo | O que faz | Camada |
|---|---|---|---|
| 01 | [bronze/01_bronze_transactions.sql](bronze/01_bronze_transactions.sql) | Materializa a Bronze com `ingestion_timestamp` e `source_file` | Bronze |
| 10 | [silver/10_silver_transactions.sql](silver/10_silver_transactions.sql) | Tipagem, limpeza, deduplicação e campos canônicos | Silver |
| 20 | [gold/20_gold_ml_input.sql](gold/20_gold_ml_input.sql) | Entrada do modelo — espelho do contrato do evento | Gold |
| 21 | [gold/21_gold_fraud_analytics.sql](gold/21_gold_fraud_analytics.sql) | Agregados de fraude para BI | Gold |
| 30 | [ml/30_create_model_logistic.sql](ml/30_create_model_logistic.sql) | Modelo v1 — regressão logística (baseline) | ML |
| 31 | [ml/31_create_model_boosted.sql](ml/31_create_model_boosted.sql) | Modelo v2 — árvores impulsionadas | ML |
| 32 | [ml/32_evaluate.sql](ml/32_evaluate.sql) | Métricas, matriz de confusão, importância e pesos | ML |
| 33 | [ml/33_predict.sql](ml/33_predict.sql) | Predição — a demonstração ao vivo | ML |

## A ingestão bruta não tem SQL

A carga do CSV do Cloud Storage para a tabela de estágio é um **load job** do
BigQuery: gratuito, paralelizado pelo próprio serviço e sem instrução SQL.
Ela é disparada por [`Notebooks/01_raw_to_bronze.ipynb`](../Notebooks/01_raw_to_bronze.ipynb).
O script `01_bronze_transactions.sql` é o passo seguinte, que acrescenta os
metadados de linhagem.

## A fronteira entre Silver e TRANSFORM

Nenhuma feature de modelo é calculada na Silver ou na Gold. `log_amount`,
`hour`, `day_of_week`, `is_night`, `age` e `distance_km` nascem dentro da
cláusula `TRANSFORM` do `CREATE MODEL`, nos scripts 30 e 31.

O motivo é arquitetural: o `TRANSFORM` é serializado junto com o modelo, então
quando ele for servido pelo Vertex AI a mesma transformação é aplicada na
inferência. Se as features fossem calculadas na Silver, existiriam duas
implementações — uma em SQL e outra na API — livres para divergir.

## Uma armadilha do dataset

As duas colunas de tempo do Sparkov discordam em **exatamente sete anos-calendário**:
`trans_date_trans_time` indica 2019–2020 e `unix_time`, na mesma linha, indica
2012–2013. A contagem em dias alterna entre 2556 e 2557 conforme quantos 29 de
fevereiro caem na janela.

A Silver adota `trans_date_trans_time` como fonte única de tempo e descarta
`unix_time`. Calcular idade a partir da coluna errada deixaria todo cliente sete
anos mais novo, sem gerar erro nenhum.
