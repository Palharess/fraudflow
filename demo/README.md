# Demonstração ao vivo · Trabalho 2

Roteiro da apresentação de 06/11/2026: o que precisa estar no ar, em que ordem
ligar, o que mostrar em cada minuto e o que fazer se algo falhar.

**Limite: 10 minutos.** Passar disso zera a nota de apresentação. O roteiro mira
**9 minutos**, e quem apresenta usa um cronômetro visível.

Prints e resultados guardados servem de apoio, mas **não substituem a
demonstração ao vivo**, que vale 60% da nota.

## O que a avaliação pede e onde aparece

| Critério | Peso | Onde no roteiro |
|---|---|---|
| Arquitetura de ponta a ponta, batch + streaming | 20% (apresentação) | blocos 1 e 2 |
| Justificativa de particionamento e processamento | (apresentação) | bloco 5 |
| Gerador → Pub/Sub → Dataflow → BigQuery ao vivo, e o papel de cada pipeline | 30% | blocos 2 e 3 |
| Requisição HTTP ao Cloud Run com predição e baixa latência | 30% | bloco 4 |
| Código e organização | 20% | links no fechamento e nos slides |

---

## Preparação

### Scripts

| Script | O que faz |
|---|---|
| `demo/preparar.sh` | instância sempre ligada na API principal, aquecimento das APIs e o job do Dataflow, esperando ficar em execução |
| `demo/conferir.sh` | gerador rodando? job em execução? linhas chegando ao BigQuery nos últimos 5 minutos? API respondendo? |
| `demo/reiniciar_dataflow.sh` | plano B: cancela o job sem worker, espera ele encerrar e sobe outro com outra máquina |
| `demo/testar_api.py` | as requisições da demo: uma fraude, uma legítima e uma entrada inválida |
| `infra/teardown.sh` | depois da apresentação: drena o job e tira a instância mínima |

Os scripts de shell rodam da raiz do repositório no Cloud Shell. Os que mexem no
Dataflow precisam do ambiente do Beam ativo: `source ~/venv-beam/bin/activate`.

### Quinta, 05/11: ensaio completo

Fazer tudo como na sexta, cronometrando todas as trocas de aba e os comandos, e
desligar no fim. Custa algo em torno de US$ 0,50, uma estimativa para cerca de
1 hora de Dataflow.

**Anotar o número da linha `Para continuar: --inicio N`** que o gerador grava no
log ao parar. Esse é o `--inicio` de sexta. Começar de uma linha já publicada não
faz a view crescer, porque ela remove as duplicatas.

### Sexta, 06/11: linha do tempo (T = início da apresentação)

| Quando | O quê |
|---|---|
| **T − 60 min** | Cloud Shell: `cd ~/fraudflow && git pull`, depois `source ~/venv-beam/bin/activate && bash demo/preparar.sh` |
| T − 45 min | Console → Dataflow → `fraudflow-stream`: conferir **1 worker** ativo. Sem worker em 15 min: plano B 1 |
| **T − 30 min** | Ligar o gerador (abaixo) com o `--inicio` anotado no ensaio |
| T − 28 min | `bash demo/conferir.sh`: tudo precisa aparecer funcionando, com linhas novas no BigQuery |
| T − 15 min | Abrir todas as abas da lista abaixo, com as consultas coladas |
| T − 5 min | `bash demo/conferir.sh` de novo |
| **Depois** | Parar o gerador (`pkill -INT -f producer/publisher.py`) e `bash infra/teardown.sh`. Conferir no console o job como **Drained** ("Reduzido") |

### O gerador, rodando em segundo plano

O gerador roda em segundo plano e grava o progresso num log. Assim, fechar a aba
do terminal não o interrompe. Isso não o protege, porém, se a máquina do Cloud
Shell for encerrada: o Cloud Shell tem limites de sessão e de inatividade.
Mantenha o log aberto e o gerador monitorado até o fim da apresentação.

1. Ligue o gerador, trocando `N` pelo número anotado no ensaio:
```bash
cd ~/fraudflow && nohup ~/venv-gerador/bin/python producer/publisher.py --inicio N --taxa 5 --invalidos 60 --intervalo-invalidos 300 > ~/gerador.log 2>&1 &
```

2. Acompanhe ao vivo; é esta tela que aparece na demo. `Ctrl+C` só fecha a visualização:
```bash
tail -f ~/gerador.log
```

3. Pare o gerador. Ele grava no log o resumo e o `--inicio` para continuar:
```bash
pkill -INT -f producer/publisher.py
```

- O ritmo é de 5 transações por segundo e um evento inválido por minuto.
- Se o `pkill -INT` não parar o gerador, use `pkill -f producer/publisher.py`.
  Nesse caso o resumo não é gravado: o próximo `--inicio` é o `--inicio` usado
  mais o número de transações da última linha do log.

### Abas abertas, nesta ordem

1. **Slides** (PDF), no diagrama da arquitetura.
2. **Cloud Shell**: uma aba com o `tail -f ~/gerador.log` e outra livre para o `testar_api.py`.
3. **Dataflow** → Jobs → `fraudflow-stream`: o grafo, e a aba de métricas com os
   contadores `eventos_validos` e `eventos_invalidos`.
4. **Pub/Sub** → Tópicos → `transactions` → Métricas: taxa de publicação.
5. **BigQuery**: uma aba por consulta (seção Consultas), já com o texto colado.
6. **GitHub**: `sql/silver/10_silver_transactions.sql`, para mostrar as regras da Silver.
7. **API** `/docs`: https://fraudflow-api-189235868606.us-central1.run.app/docs

---

## Roteiro (9 minutos)

Os slides (`entrega/FraudFlow_Trabalho2_slides.pptx`, 6 slides, com as falas nas
notas) abrem e fecham a apresentação; a demonstração ao vivo acontece entre o
slide 3 e o 4.

| Tempo | Bloco | Onde |
|---|---|---|
| 0:00–1:15 | 1. Problema, evolução e arquitetura | slides 1 e 2 |
| 1:15–1:45 | O caminho de uma transação | slide 3 |
| 1:45–2:45 | 2. O papel do batch | GitHub e BigQuery, ao vivo |
| 2:45–5:30 | 3. O streaming | Cloud Shell, Dataflow, Pub/Sub e BigQuery, ao vivo |
| 5:30–7:15 | 4. A API | Cloud Shell e /docs, ao vivo |
| 7:15–8:45 | 5. Decisões, problemas e caminhos alternativos | slides 4 e 5 |
| 8:45–9:00 | 6. Fechamento | slide 6 |

### 1. O problema e a evolução · slides 1 a 3

> Detectamos fraude em transações de cartão. No Trabalho 1, construímos o
> histórico em lote no BigQuery e treinamos o modelo. No Trabalho 2, as
> transações passam a chegar em tempo real, e o modelo responde por uma API.

- Mostrar o diagrama: as três camadas (batch, streaming e serviço).
- Explicar o **replay**: as transações de 2020 do `fraudTest` são publicadas agora, uma por vez.

### 2. O papel do batch · GitHub e BigQuery

> O pipeline batch processa o histórico inteiro de uma vez, da Bronze à Gold. É
> dele que sai o modelo.

- **GitHub:** o SQL da Silver, com tipagem, limpeza, remoção de duplicatas e as
  regras de validade.
- **Consulta B**, executada ao vivo: a mesma transformação aplicada a 5 linhas da
  Bronze. O texto cru vira horário e número, e o prefixo `fraud_` sai.
- **Consulta A:** o volume em cada camada, 1.296.675 linhas da Bronze à Gold.

### 3. O streaming ao vivo · Cloud Shell, Dataflow, Pub/Sub, BigQuery

> O pipeline de streaming trata cada transação assim que ela chega, com as
> mesmas regras da Silver.

1. **Gerador** (`tail -f ~/gerador.log`): os eventos sendo publicados.
2. **Dataflow:** o grafo, e os contadores de válidos e inválidos subindo.
3. **Consulta 1**, primeira vez: quantas transações já chegaram pelo stream.
4. Enquanto o tempo passa, mostrar o **Pub/Sub** (taxa de mensagens) e a
   **consulta 4**: os eventos inválidos registrados com o motivo, sem derrubar o
   pipeline.
5. **Consulta 1** de novo: a linha `stream` cresceu, e a `batch` continua igual.
   Esta é a relação batch + streaming.
6. **Consulta 2**, a emenda: o histórico termina às 12:13:37 e o stream começa às
   12:14:25, na mesma view. O `is_fraud` vazio no stream é proposital.
7. **Consulta 3**, o atraso entre a publicação e o início do processamento.

### 4. A API ao vivo · Cloud Shell e /docs

> A API recebe uma transação e devolve o score de fraude. O modelo está dentro
> do container.

```bash
python3 demo/testar_api.py
```

- Uma fraude e uma legítima reais da validação: o `fraud_score` de cada uma, a
  latência e o rótulo revelado só depois da resposta.
- A entrada inválida: erro 422, explicando cada campo.
- No `/docs`: o contrato, e um *Try it out* se houver tempo.
- A contingência (`--contingencia`) só entra se a principal falhar ou se o
  professor perguntar.

### 5. Decisões, problemas e caminhos alternativos · slides 4 e 5

- **Partição pela data da transação e cluster por categoria**, nas duas camadas:
  consultas por período leem só as partições do período. A consulta 2 mostra a
  estimativa de bytes lidos. A tabela de erros é particionada pela data de
  processamento.
- **Horário original do evento**: hora e madrugada decidem o modelo. O horário de
  publicação e o de processamento ficam em colunas separadas.
- **Duplicatas**: o Pub/Sub entrega pelo menos uma vez. O Dataflow descarta
  reenvios recentes, e a view mantém uma linha por transação.
- **Caminhos alternativos** (slide 5): o endpoint do Vertex AI não subiu por
  falta de máquina, então o modelo foi para dentro da API (Docker no Cloud Run),
  com a contingência pelo `ML.PREDICT`; no streaming, se faltar worker, outro tipo
  de máquina e, em último caso, o executor local.
- **Problemas que os testes pegaram**: a exportação recusada pela idade em texto,
  o `is_night` que virava ausente (paridade de 0,86 para 0) e a API fria.

### 6. Fechamento · slide 6

- Os links: o GitHub com o código e o README, e a URL da API.
- O próximo passo, no Trabalho Final: o Dataflow chama esta API para cada
  transação e grava o score junto com o evento.

---

## Consultas

Prontas para colar no BigQuery. As de número 1 a 4 também estão em
[`sql/stream/42_consultas_demo.sql`](../sql/stream/42_consultas_demo.sql).

**A · Volume em cada camada do batch**
```sql
SELECT 'bronze' AS camada, COUNT(*) AS linhas FROM `fraudflow-pdm-gps.bronze.transactions`
UNION ALL SELECT 'silver', COUNT(*) FROM `fraudflow-pdm-gps.silver.transactions`
UNION ALL SELECT 'gold.ml_input', COUNT(*) FROM `fraudflow-pdm-gps.gold.ml_input`;
```

**B · A transformação da Silver em 5 linhas da Bronze**
```sql
SELECT
  trans_date_trans_time, amt, merchant,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', trans_date_trans_time) AS transaction_ts,
  SAFE_CAST(amt AS FLOAT64)                                        AS amount,
  REGEXP_REPLACE(merchant, r'^fraud_', '')                         AS merchant_name
FROM `fraudflow-pdm-gps.bronze.transactions`
LIMIT 5;
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

**3 · Atraso entre a publicação e o início do processamento (últimos 10 minutos)**
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
| 1. Dataflow sem worker depois de 15 min | `MAQUINA=e2-standard-2 bash demo/reiniciar_dataflow.sh`: cancela o job, espera ele encerrar e sobe outro |
| 2. Dataflow não sobe de jeito nenhum | Contingência degradada, e deve ser apresentada como tal. Confirmar que **nenhum** job do Dataflow está ativo, porque os dois não podem ler a mesma assinatura. Então rodar `bash streaming/run.sh local`: mesmo código e mesmas tabelas, no executor local do Beam |
| 3. O gerador parou | `bash demo/conferir.sh` mostra. Ligar de novo com o `--inicio` seguinte, tirado do log |
| 4. A API principal lenta ou fora | `python3 demo/testar_api.py --contingencia`: a mesma predição pelo `ML.PREDICT` |
| 5. Console do BigQuery lento | Seguir o roteiro com os resultados registrados nos slides |
| 6. Sem internet | Slides com as evidências; o código no GitHub fica para a avaliação |

**Nunca apresentar com a API fria.** Medido em 03/11: depois de a API ficar
parada, a primeira requisição levou cerca de um minuto, porque o container sobe e
carrega o TensorFlow. O `demo/preparar.sh` deixa uma instância ligada e faz uma
requisição de aquecimento.

## Custos do dia

Estimativas, para cerca de 2 horas ligadas:
- **Dataflow** (1 worker): na casa de US$ 0,50.
- **Instância mínima do Cloud Run:** centavos.
- **Pub/Sub e BigQuery:** centavos.

O `infra/teardown.sh` desliga o que cobra por hora, e não apaga dados.
