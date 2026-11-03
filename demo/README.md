# Demonstração ao vivo · Trabalho 2

Roteiro da apresentação de 06/11/2026: o que precisa estar no ar, em que ordem
ligar, o que mostrar em cada minuto e o que fazer se algo falhar.

**Limite: 10 minutos.** Passar disso zera a nota de apresentação. O roteiro mira
**9 minutos**, e quem apresenta usa um cronômetro visível.

## O que a avaliação pede e onde aparece

| Critério | Peso | Onde no roteiro |
|---|---|---|
| Arquitetura de ponta a ponta, batch + streaming | 20% (apresentação) | blocos 1 e 2 |
| Justificativa de particionamento e processamento | (apresentação) | blocos 3 e 5 |
| Gerador → Pub/Sub → Dataflow → BigQuery ao vivo, e o papel de cada pipeline | 30% | blocos 2 e 3 |
| Requisição HTTP ao Cloud Run com predição e baixa latência | 30% | bloco 4 |
| Código e organização | 20% | link do GitHub nos slides |

---

## Preparação

### Quinta, 05/11: ensaio completo

Fazer tudo como na sexta, cronometrando, e desligar no fim. Custa algo em torno
de US$ 0,50 (Dataflow por cerca de 1 hora), uma estimativa. Anotar o número
`Para continuar: --inicio N` que o gerador imprime ao parar: é o `--inicio` de sexta.

### Sexta, 06/11: linha do tempo (T = início da apresentação)

| Quando | O quê |
|---|---|
| **T − 60 min** | Cloud Shell: `cd ~/fraudflow && git pull`, depois `source ~/venv-beam/bin/activate && bash demo/preparar.sh` |
| T − 45 min | Console → Dataflow → `fraudflow-stream`: conferir **Em execução** com 1 worker. Sem worker em 15 min: plano B 1 |
| **T − 30 min** | Ligar o gerador em segundo plano (abaixo) e conferir, com a consulta 1, que o stream está crescendo |
| T − 15 min | `python3 demo/testar_api.py` uma vez (aquece a API) e abrir todas as abas da lista abaixo |
| T − 5 min | Rodar de novo as consultas 1 e 3; conferir que o gerador continua imprimindo |
| **Depois** | Parar o gerador (`pkill -INT -f producer/publisher.py`) e `bash infra/teardown.sh`. Conferir no console o job como **Drained** ("Reduzido") |

### O gerador, rodando em segundo plano

O gerador roda em segundo plano e grava o progresso num arquivo de log. Assim,
ele continua mesmo se a aba do terminal fechar:

1. Ligue o gerador:
```bash
cd ~/fraudflow && nohup ~/venv-gerador/bin/python producer/publisher.py --inicio 1200 --taxa 5 --invalidos 60 --intervalo-invalidos 300 > ~/gerador.log 2>&1 &
```

2. Acompanhe ao vivo; é esta tela que aparece na demo. `Ctrl+C` só fecha a visualização:
```bash
tail -f ~/gerador.log
```

3. Pare o gerador. Ele grava no log o resumo e o `--inicio` para continuar:
```bash
pkill -INT -f producer/publisher.py
```

- Se o `pkill -INT` não parar o gerador, use `pkill -f producer/publisher.py`.
  Nesse caso o resumo não é gravado: o próximo `--inicio` é o `--inicio` usado
  mais o número de transações da última linha do log.
- O ritmo é de 5 transações por segundo e um evento inválido por minuto.
- O `--inicio` deve ser o número anotado no ensaio de quinta.

### Abas abertas, nesta ordem

1. **Slides** (PDF), no diagrama da arquitetura.
2. **Cloud Shell**: uma aba com o `tail -f ~/gerador.log` e outra livre para o `testar_api.py`.
3. **Pub/Sub** → Tópicos → `transactions` → Métricas: taxa de publicação.
4. **Dataflow** → Jobs → `fraudflow-stream`: o grafo, e a aba de métricas com os
   contadores `eventos_validos` e `eventos_invalidos`.
5. **BigQuery**, uma aba por consulta (seção Consultas), já com o texto colado.
6. **API** `/docs`: https://fraudflow-api-189235868606.us-central1.run.app/docs

---

## Roteiro (9 minutos)

### 1. O problema e a evolução · 0:00–1:00 · slides

> Detectamos fraude em transações de cartão. No Trabalho 1, construímos o
> histórico em lote no BigQuery e treinamos o modelo. No Trabalho 2, as
> transações passam a chegar em tempo real, e o modelo responde por uma API.

Mostrar o diagrama: as três camadas, batch, streaming e serviço, e a ideia de
**replay** (o `fraudTest` de 2020 publicado agora, uma transação por vez).

### 2. O papel do batch · 1:00–2:00 · BigQuery

> O pipeline batch processa o histórico inteiro de uma vez: 1,3 milhão de
> transações, da Bronze à Gold. É dele que sai o modelo.

- **Consulta A** (camadas do batch): as mesmas 1.296.675 linhas da Bronze à Gold.
- No explorador do BigQuery, apontar `bronze`, `silver`, `gold` e o modelo `fraud_boosted`.

### 3. O streaming ao vivo · 2:00–5:30 · Cloud Shell, Pub/Sub, Dataflow, BigQuery

> O pipeline de streaming trata cada transação assim que ela chega, com as
> mesmas regras de limpeza da Silver.

1. **Gerador** (Cloud Shell, `tail -f ~/gerador.log`): mostrar os eventos sendo publicados.
2. **Pub/Sub**: a taxa de mensagens no tópico.
3. **Dataflow**: o grafo e os contadores de válidos e inválidos subindo.
4. **Consulta 1**, duas vezes, com uns 20 s entre elas: a linha `stream` cresce e
   a `batch` fica parada. Esta é a relação batch + streaming.
5. **Consulta 2** (a emenda): o histórico termina às 12:13:37 e o stream começa às
   12:14:25, na mesma view. O `is_fraud` vazio no stream é proposital.
6. **Consulta 4** (erros): os eventos inválidos ficam registrados com o motivo, em
   vez de derrubar o pipeline.
7. **Consulta 3** (atraso): da publicação até o início do processamento, em milissegundos.

### 4. A API ao vivo · 5:30–7:45 · Cloud Shell e /docs

> A API recebe uma transação e devolve o score de fraude. O modelo está dentro
> do container, sem depender de nenhum outro serviço.

```bash
python3 demo/testar_api.py
```

- Uma fraude e uma legítima reais da validação. Mostrar o `fraud_score` de cada
  uma, a latência e o rótulo revelado só depois da resposta.
- A entrada inválida: erro 422, explicando cada campo.
- Abrir o `/docs` e mostrar o contrato.
- Se sobrar tempo: `python3 demo/testar_api.py --contingencia`, a mesma resposta
  pelo `ML.PREDICT`, mais lenta.

### 5. Por que essas escolhas · 7:45–8:45 · slides

- **Partição pela data da transação e cluster por categoria**, nas duas camadas:
  consultas por período leem só as partições do período. A consulta 2 mostra a
  estimativa de bytes lidos. A tabela de erros é particionada pela data de
  processamento.
- **Horário do evento, não de chegada**: hora e madrugada decidem o modelo.
- **Duplicatas**: o Pub/Sub entrega pelo menos uma vez; o Dataflow e a view
  removem as repetições.
- **Modelo no container**: o Vertex AI ficou sem máquina na região. Carregar o
  modelo na API tirou essa dependência e baixou a latência. O teste de paridade
  provou que o resultado é idêntico ao do BigQuery.

### 6. Fechamento · 8:45–9:00

> Próximo passo, no trabalho final: o Dataflow chama esta API para cada
> transação e grava o score junto com o evento.

---

## Consultas

Prontas para colar no BigQuery. As de número 1 a 4 também estão em
[`sql/stream/42_consultas_demo.sql`](../sql/stream/42_consultas_demo.sql).

**A · Camadas do batch**
```sql
SELECT 'bronze' AS camada, COUNT(*) AS linhas FROM `fraudflow-pdm-gps.bronze.transactions`
UNION ALL SELECT 'silver', COUNT(*) FROM `fraudflow-pdm-gps.silver.transactions`
UNION ALL SELECT 'gold.ml_input', COUNT(*) FROM `fraudflow-pdm-gps.gold.ml_input`;
```

**1 · Batch e stream lado a lado**
```sql
SELECT origin, COUNT(*) AS transacoes, MIN(transaction_ts) AS primeira, MAX(transaction_ts) AS ultima, MAX(arrived_at) AS ultima_chegada
FROM `fraudflow-pdm-gps.gold.vw_transactions_unified`
GROUP BY origin ORDER BY origin;
```

**2 · A emenda**
```sql
SELECT origin, FORMAT_TIMESTAMP('%d/%m/%Y %H:%M:%S', transaction_ts) AS quando, category, ROUND(amount, 2) AS valor, is_fraud
FROM `fraudflow-pdm-gps.gold.vw_transactions_unified`
WHERE DATE(transaction_ts) = '2020-06-21' AND transaction_ts BETWEEN '2020-06-21 12:10:00' AND '2020-06-21 12:20:00'
ORDER BY transaction_ts;
```

**3 · Atraso do pipeline (últimos 10 minutos)**
```sql
SELECT COUNT(*) AS eventos,
  ROUND(AVG(TIMESTAMP_DIFF(processed_at, published_at, MILLISECOND))) AS atraso_medio_ms,
  APPROX_QUANTILES(TIMESTAMP_DIFF(processed_at, published_at, MILLISECOND), 100)[OFFSET(95)] AS atraso_p95_ms
FROM `fraudflow-pdm-gps.silver.transactions_stream`
WHERE processed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);
```

**4 · Erros por motivo (hoje)**
```sql
SELECT error_reason, COUNT(*) AS eventos, MAX(processed_at) AS ultimo
FROM `fraudflow-pdm-gps.silver.transactions_stream_errors`
WHERE DATE(processed_at) = CURRENT_DATE()
GROUP BY error_reason ORDER BY eventos DESC;
```

---

## Plano B

| Se acontecer | Fazer |
|---|---|
| 1. Dataflow sem worker depois de 15 min | `bash infra/teardown.sh`, depois `MAQUINA=e2-standard-2 bash demo/preparar.sh` |
| 2. Dataflow não sobe de jeito nenhum | Rodar o mesmo pipeline no Cloud Shell: `bash streaming/run.sh local`. Mesmo código e mesmas tabelas; avisar que é o executor local e mostrar o grafo do Dataflow nos slides |
| 3. O gerador parou | Ver a última linha de `~/gerador.log` e ligar de novo com o `--inicio` seguinte |
| 4. A API principal lenta ou fora | `python3 demo/testar_api.py --contingencia`: a mesma predição pelo `ML.PREDICT` |
| 5. Console do BigQuery lento | Mostrar os resultados registrados nos slides e seguir o roteiro |
| 6. Sem internet | Slides com as evidências; o código no GitHub fica para a avaliação |

**Nunca apresentar com a API fria.** A primeira chamada depois de a API ficar
parada leva cerca de um minuto, porque o container sobe e carrega o TensorFlow.
O `demo/preparar.sh` deixa uma instância ligada, e o aquecimento das T − 15 min
confirma.

## Custos do dia

Estimativas, para cerca de 2 horas ligadas:
- **Dataflow** (1 worker): na casa de US$ 0,50.
- **Instância mínima do Cloud Run:** centavos.
- **Pub/Sub e BigQuery:** centavos.

O `infra/teardown.sh` desliga tudo isso, e não apaga dados.
