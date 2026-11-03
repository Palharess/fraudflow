# Evidências dos testes · Trabalho 2

Saídas reais dos testes, executados entre 02 e 03/11/2026 no projeto
`fraudflow-pdm-gps`. Foram tiradas só as linhas de ruído: avisos do TensorFlow
sobre GPU e logs de instalação. A ordem segue a do trabalho.

---

## 1. Modelo registrado e exportado (notebook 05, Parte A)

Depois do retreino com a idade numérica:

```
BigQuery ML
  modelo           fraudflow-pdm-gps.gold.fraud_boosted
  tipo             BOOSTED_TREE_CLASSIFIER
  atualizado em    02/11/2026 21:34 UTC

Model Registry
  recurso          projects/189235868606/locations/us-central1/models/fraudflow-boosted
  versão padrão    2
  tipos de deploy aceitos  ['DEDICATED_RESOURCES']

Versões registradas
  v2    criada em 2026-11-02 21:29:27.928015+00:00   aliases=['default']

Exportação concluída: gs://fraudflow-pdm-gps-data/models/fraud_boosted/20261102_221500/
  assets/2_categorical_label.txt
  assets/5_categorical_label.txt
  assets/model_metadata.json
  explanation_metadata.json
  main.py
  model.bst
  transform/fingerprint.pb
  transform/saved_model.pb
  transform/variables/variables.data-00000-of-00001
  transform/variables/variables.index
  xgboost_predictor-0.1.tar.gz
```

## 2. Por que a primeira exportação falhou (notebook 05, Parte A2)

Primeira tentativa, antes da correção:

```
Model export with TRANSFORM only supports numerical type arguments of function $less,
but was given type STRING.
```

As duas fórmulas de idade dão o mesmo resultado em toda a tabela:

```
linhas    idades_diferentes
1296675   0
```

Modelos mínimos de teste:

```
export_teste_atual       FALHOU    (idade comparada como texto: mesmo erro)
export_teste_idade_num   EXPORTOU  (idade comparada como número)
```

## 3. Métricas depois do retreino (notebook 04)

```
modelo              recall   precision  f1      roc_auc  accuracy
v1 · logistica      0.8667   0.0412     0.0786  0.9493   0.8794
v2 · boosted tree   0.9701   0.3069     0.4662  0.9984   0.9868

Matriz de confusão do v2 (limiar 0,5)
                 previsto 0   previsto 1
real 0           254626       3370
real 1           46           1492
```

## 4. Endpoint do Vertex AI sem máquina disponível (notebook 05, Parte B)

```
implantando em e2-standard-2...
sem capacidade para e2-standard-2 agora: 503 Machine type temporarily unavailable,
please deploy with a different machine type or retry
implantando em n2-standard-2...
sem capacidade para n2-standard-2 agora: 503 Machine type temporarily unavailable, ...
implantando em n1-standard-2...
sem capacidade para n1-standard-2 agora: 503 Machine type temporarily unavailable, ...
```

Cota do projeto na região: *Custom model serving CPUs per region* = 24, uso 0.

## 5. Paridade dentro da imagem Docker (`api/scripts/paridade.py`)

O modelo exportado, dentro da imagem que vai para o Cloud Run, comparado com o
BigQuery nas mesmas 50 transações da janela de validação:

```
modelo: fraudflow-boosted v2 · gs://fraudflow-pdm-gps-data/models/fraud_boosted/20261102_221500

Entradas do TRANSFORM:
  amount           float64
  category         string
  city_pop         int64
  customer_dob     string
  customer_lat     float64
  customer_long    float64
  merchant_lat     float64
  merchant_long    float64
  transaction_ts   string

com +00        aceito   diferença máxima 0.00e+00
texto simples  recusado
com UTC        recusado
ISO com Z      recusado

Features comparadas com o ML.TRANSFORM em 50 de 50 transações:
  amount       diferença máxima 0.00e+00
  log_amount   diferença máxima 8.88e-16
  category     0 diferentes
  hour         diferença máxima 0.00e+00
  day_of_week  diferença máxima 0.00e+00
  is_night     0 diferentes
  age          diferença máxima 0.00e+00
  distance_km  diferença máxima 1.42e-14
  city_pop     diferença máxima 0.00e+00

formato escolhido: com +00 ('%Y-%m-%d %H:%M:%S+00')
diferença máxima de score: 0.00e+00

Latência da inferência, uma transação por vez, sem HTTP:
  primeira 2.8 ms · mediana 2.2 ms · pior 3.7 ms

  [ok] 50 transações na amostra
  [ok] 50 transaction_id distintos
  [ok] fraudes e legítimas presentes
  [ok] features iguais às do ML.TRANSFORM
  [ok] algum formato de TIMESTAMP bateu
  [ok] 50 scores devolvidos
  [ok] scores finitos entre 0 e 1
  [ok] diferença máxima < 0.0001

PARIDADE CONFIRMADA · fraudflow-boosted v2
```

Antes da correção do `is_night`, o mesmo teste mostrava:

```
com +00        aceito   diferença máxima 8.59e-01
```

## 6. API principal publicada, testada por HTTP (`api/scripts/paridade_http.py`)

```
/health  200  98 ms  {'status': 'ok', 'backend': 'modelo-local', 'modelo': 'fraudflow-boosted v2 · ...'}

backend: modelo-local
diferença máxima de score: 4.99e-07
Latência HTTP de ponta a ponta, do Cloud Shell:
  primeira 441 ms · mediana 51 ms · pior 234 ms
Entrada inválida (amount = 0): 422 · Input should be greater than 0

  [ok] /health respondeu 200
  [ok] 50 respostas 200
  [ok] transaction_id devolvido em cada resposta
  [ok] diferença máxima < 0.0001
  [ok] entrada inválida recusada com 422

API APROVADA · https://fraudflow-api-eflb2lisiq-uc.a.run.app
```

A diferença de 4.99e-07 é o arredondamento do score para 6 casas na resposta.

## 7. API de contingência publicada, testada por HTTP

```
/health  200  110 ms  {'status': 'ok', 'backend': 'bigquery-ml-predict', 'modelo': 'gold.fraud_boosted · BigQuery ML · treinado em 02/11/2026 21:34 UTC'}

backend: bigquery-ml-predict
diferença máxima de score: 4.99e-07
Latência HTTP de ponta a ponta, do Cloud Shell:
  primeira 1140 ms · mediana 613 ms · pior 1230 ms
Entrada inválida (amount = 0): 422 · Input should be greater than 0

  [ok] /health respondeu 200
  [ok] 50 respostas 200
  [ok] transaction_id devolvido em cada resposta
  [ok] diferença máxima < 0.0001
  [ok] entrada inválida recusada com 422

API APROVADA · https://fraudflow-api-bq-eflb2lisiq-uc.a.run.app
```

## 8. Streaming com o pipeline no Cloud Shell (DirectRunner)

Gerador:

```
Publicando gs://fraudflow-pdm-gps-data/holdout/fraudTest.csv → transactions a 10 eventos/s (linhas 0 a 200)
  primeira linha lida em 1.2 s
200 transações e 6 inválidos de teste em 21 s (10.0/s)
Período reproduzido: 2020-06-21 12:14:25 → 2020-06-21 13:21:16
```

Contagem nas tabelas:

```
tabela    linhas
validas   200
erros     6
```

A emenda entre histórico e tempo real na `gold.vw_transactions_unified`:

```
origin  quando               category        valor   is_fraud
batch   21/06/2020 12:12:32  food_dining     105.93  0
batch   21/06/2020 12:13:36  food_dining     74.9    0
batch   21/06/2020 12:13:37  food_dining     4.3     0
stream  21/06/2020 12:14:25  personal_care   2.86
stream  21/06/2020 12:14:33  personal_care   29.84
stream  21/06/2020 12:14:53  health_fitness  41.28
```

Erros por motivo:

```
error_reason                          eventos  exemplo_id
campo_ausente:amt                     1        teste-invalido-50f4441619df
fora_do_intervalo:customer_lat        1        teste-invalido-d55bff8253aa
json_invalido                         1        teste-invalido-c51ce372e605
nascimento_apos_transacao             1        teste-invalido-3ba914bc5c60
tipo_invalido:trans_date_trans_time   1        teste-invalido-0a37dd1c2c85
valor_nao_positivo                    1        teste-invalido-9cb02873756f
```

## 9. Streaming no Dataflow

Job `fraudflow-stream` (2026-11-03_07_13_52-17010001497972538288), 1 worker
n1-standard-2. Nos primeiros minutos, o Dataflow avisou *Startup of the worker
pool in us-central1 failed to bring up any of the desired 1 workers* (falta de
máquina na região), tentou de novo sozinho e começou a processar.

Gerador, continuando o replay:

```
Publicando gs://fraudflow-pdm-gps-data/holdout/fraudTest.csv → transactions a 20 eventos/s (linhas 200 a 1200)
1000 transações e 6 inválidos de teste em 50 s (20.0/s)
Período reproduzido: 2020-06-21 13:21:20 → 2020-06-21 19:03:09
```

Republicação das 50 primeiras, para o teste de duplicatas:

```
Publicando ... (linhas 0 a 50)
50 transações e 0 inválidos de teste em 3 s (20.0/s)
```

Consulta 1 · as duas origens na view:

```
origin  transacoes  primeira_transacao       ultima_transacao         ultima_chegada
batch   1296675     2019-01-01 00:00:18 UTC  2020-06-21 12:13:37 UTC  2026-09-04 12:14:34 UTC
stream  1200        2020-06-21 12:14:25 UTC  2020-06-21 19:03:09 UTC  2026-11-03 15:23:45 UTC
```

Consulta 3 · atraso da publicação no Pub/Sub até o início do processamento no Beam
(`processed_at` é marcado quando o pipeline recebe o evento, antes da gravação no
BigQuery):

```
eventos  atraso_medio_ms  atraso_p95_ms
1050     560              3189
```

Consulta 5 · duplicatas:

```
linhas_na_tabela  transacoes_distintas  linhas_na_view
1250              1200                  1200
```

Desligamento (`infra/teardown.sh`):

```
== Dataflow
Started draining job [2026-11-03_07_13_52-17010001497972538288]
== Vertex AI
  apagado: 7979864518014533632
```

O job terminou no estado *Drained* (no console em português, "Reduzido").
