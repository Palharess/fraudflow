# Demonstração ao vivo · Trabalho 2

Roteiro da apresentação de 06/11/2026, em quatro fases:

| Fase | Quando | Duração |
|---|---|---|
| **1. Preparar** | 1 hora antes | ~20 min, quase tudo esperando |
| **2. Slides** | início da apresentação | ~4 min |
| **3. Demonstração ao vivo** | logo depois dos slides | ~5 min |
| **4. Desligar** | depois da apresentação | 5 min |

**Limite: 10 minutos** (fases 2 e 3). Passar disso zera a nota de apresentação.
O roteiro mira **9 minutos**: use um cronômetro visível.

A demonstração ao vivo vale 60% da nota: o gerador publicando, o Dataflow
processando, os dados chegando ao BigQuery e uma requisição à API no Cloud Run.

---

## 1. Antes da apresentação: preparar

Tudo roda no **Cloud Shell**. Ao fim desta fase, o streaming já está funcionando
sozinho e a API está aquecida: na hora, você só **mostra**.

**T − 60 min · Ligar a API e o Dataflow**

1. Atualize o repositório e ative o ambiente do Beam:
```bash
cd ~/fraudflow && git pull && source ~/venv-beam/bin/activate
```

2. Rode a preparação:
```bash
bash demo/preparar.sh
```

O script faz três coisas:
- liga uma instância fixa na API principal;
- aquece as duas APIs;
- sobe o job no Dataflow e espera ficar `JOB_STATE_RUNNING`.

**T − 45 min · Conferir o worker do Dataflow**

Console → **Dataflow** → `fraudflow-stream`. Na lateral do job, espere **1 worker
atual**. Se em 15 minutos não houver worker, use o plano B 1 (fim deste arquivo).

**T − 30 min · Ligar o gerador**

1. Entre na pasta do projeto. É um comando separado: se o `cd` estivesse na
   mesma linha do `&` do passo 2, ele iria junto para o segundo plano.
```bash
cd ~/fraudflow
```

2. Ligue o gerador, com o `--inicio` anotado no ensaio (fase 4):
```bash
nohup ~/venv-gerador/bin/python producer/publisher.py --inicio N --taxa 5 --invalidos 60 --intervalo-invalidos 300 > ~/gerador.log 2>&1 &
```

O gerador publica 5 transações por segundo e um evento inválido por minuto, em
segundo plano. Ele grava o progresso em `~/gerador.log`.

**T − 28 min · Conferir que tudo funciona**
```bash
bash demo/conferir.sh
```

O esperado:
- o gerador aparece **rodando**;
- o job aparece **JOB_STATE_RUNNING**;
- `validas_5min` dá algumas centenas;
- `erros_5min` dá 1 ou mais;
- a API responde **200** em menos de 1 s.

**T − 15 min · Abrir as abas**, nesta ordem:

1. **Slides**, no PowerPoint, em modo apresentação.
2. **Cloud Shell, aba 1** com o gerador ao vivo: `tail -f ~/gerador.log`
3. **Cloud Shell, aba 2**, livre, já em `~/fraudflow`, para o teste da API.
4. **Dataflow** → `fraudflow-stream`, no grafo.
5. **BigQuery**, com seis abas, uma por consulta, já coladas (seção
   [Consultas](#consultas)): **B, A, 1, 4, 2, 3**.
6. **API**: https://fraudflow-api-189235868606.us-central1.run.app/docs

Aumente o zoom do navegador (`Ctrl` + `+`) e a fonte do Cloud Shell, para a projeção.

**T − 5 min · Conferir de novo**
```bash
bash demo/conferir.sh
```

---

## 2. Slides (~4 min)

As falas completas estão nas notas de cada slide.

| Slide | Tempo | O que dizer, em resumo |
|---|---|---|
| 1 · Capa | 0:30 | Detectamos fraude em cartão. No T1, o histórico em lote e o modelo; no T2, as transações chegando em tempo real e o modelo numa API. Três camadas: batch, streaming e serviço |
| 2 · Arquitetura | 1:00 | **Azul**: o batch (Bronze, Silver, Gold, modelo). **Verde**: o streaming (gerador com replay de 2020 → Pub/Sub → Dataflow com as mesmas regras da Silver). A view junta os dois. **Laranja**: o modelo dentro da API no Cloud Run |
| 3 · Caminho de uma transação | 0:30 | Gerador, fila, Dataflow, BigQuery e view. A emenda: o histórico termina às 12:13:37 e o stream começa às 12:14:25. A API funciona em paralelo |
| 4 · Decisões | 0:45 | Partição por data (a consulta lê só o período); horário original (hora e madrugada decidem o modelo); duplicatas em duas camadas; erro registrado, não descartado |
| 5 · Problemas e caminhos | 1:00 | O Vertex AI não subiu, então o modelo foi para dentro da API (Docker), com a contingência pelo ML.PREDICT; no Dataflow, se faltar máquina, troca o tipo; o teste de paridade pegou um erro silencioso |
| 6 · Resultados | 0:30 | 97 de cada 100 fraudes; o mesmo resultado fora do BigQuery; API em 51 ms. **"Agora vamos ver tudo isso funcionando."** |

---

## 3. Demonstração ao vivo (~5 min)

Tudo já está rodando: você só troca de aba e executa.

### A. O batch · 0:45 · BigQuery

| Fazer | Dizer |
|---|---|
| Executar a **consulta B** | "O batch transforma o histórico. Aqui, a regra da Silver em 5 linhas da Bronze: o texto vira horário e número, e o prefixo `fraud_` sai." |
| Executar a **consulta A** | "1.296.675 transações da Bronze à Gold. É desse histórico que sai o modelo." |

### B. O streaming · 2:30 · Cloud Shell, Dataflow, BigQuery

| Fazer | Dizer |
|---|---|
| **Cloud Shell, aba 1** (o `tail -f`) | "Este é o gerador publicando agora, 5 transações por segundo. Os horários são de 2020: mantemos o horário original da compra." |
| **Dataflow**, o grafo | "O Dataflow lê a fila, aplica as regras da Silver e separa válidas e erros." |
| Executar a **consulta 1** e guardar o número da linha `stream` | "A linha batch é o histórico; a linha stream, o que chegou pelo pipeline." |
| Executar a **consulta 4** | "Um evento inválido por minuto. Ele não derruba o pipeline: fica registrado com o motivo." |
| Executar a **consulta 1** de novo | "O stream cresceu, e o batch continua igual. Os dois pipelines alimentam a mesma visão." |
| Executar a **consulta 2**; apontar o "vai processar … KB" | "A emenda: o histórico termina às 12:13:37 e o stream começa às 12:14:25. Por causa da partição, a consulta leu só alguns KB." |
| Executar a **consulta 3** | "Da publicação até o início do processamento, em milissegundos." |

### C. A API · 1:30 · Cloud Shell, aba 2, e /docs

| Fazer | Dizer |
|---|---|
| Rodar `python3 demo/testar_api.py` | "Duas transações reais da validação. Olhem o `fraud_score` e a latência. Só depois da resposta mostramos o rótulo real." |
| Apontar a terceira resposta (422) | "Uma entrada inválida: a API recusa e explica cada campo." |
| Abrir o **/docs** | "Este é o contrato da API, gerado automaticamente." |

### D. Fechamento · 0:15

> "O código, o README e as evidências estão no GitHub. No Trabalho Final, o
> Dataflow vai chamar esta API para cada transação."

A contingência (`python3 demo/testar_api.py --contingencia`) só entra se a API
principal falhar ou se o professor perguntar.

---

## 4. Depois: desligar

1. Pare o gerador:
```bash
pkill -INT -f producer/publisher.py
```

2. Veja o resumo do gerador e **anote o número** da linha `Para continuar: --inicio N`. É o `--inicio` da próxima vez:
```bash
tail -n 4 ~/gerador.log
```

3. Desligue o que cobra por hora (drena o Dataflow e tira a instância fixa da API):
```bash
cd ~/fraudflow && bash infra/teardown.sh
```

4. No console, confira o job como **Drained** ("Reduzido").

Se o `pkill -INT` não parar o gerador, use `pkill -f producer/publisher.py`.
Nesse caso o resumo não é gravado, e o próximo `--inicio` é o `--inicio` usado
mais o número de transações da última linha do log.

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

## Scripts

| Script | O que faz |
|---|---|
| `demo/preparar.sh` | instância fixa na API principal, aquecimento das APIs e o job do Dataflow, esperando ficar em execução |
| `demo/conferir.sh` | gerador rodando? job em execução? linhas chegando ao BigQuery nos últimos 5 minutos? API respondendo? |
| `demo/reiniciar_dataflow.sh` | plano B: cancela o job sem worker, espera ele encerrar e sobe outro com outra máquina |
| `demo/testar_api.py` | as requisições da demo: uma fraude, uma legítima e uma entrada inválida |
| `infra/teardown.sh` | depois da apresentação: drena o job e tira a instância fixa da API |

## Plano B

| Se acontecer | Fazer |
|---|---|
| 1. Dataflow sem worker depois de 15 min | `MAQUINA=e2-standard-2 bash demo/reiniciar_dataflow.sh` (com o ambiente do Beam ativo): cancela o job, espera ele encerrar e sobe outro |
| 2. Dataflow não sobe de jeito nenhum | Contingência degradada, e deve ser apresentada como tal. Confirmar que **nenhum** job do Dataflow está ativo, porque os dois não podem ler a mesma assinatura. Então rodar `bash streaming/run.sh local`: mesmo código e mesmas tabelas, no executor local do Beam |
| 3. O gerador parou | `bash demo/conferir.sh` mostra. Ligar de novo com o `--inicio` seguinte, tirado do log |
| 4. A API principal lenta ou fora | `python3 demo/testar_api.py --contingencia`: a mesma predição pelo `ML.PREDICT` |
| 5. Console do BigQuery lento | Seguir o roteiro com os resultados registrados nos slides |
| 6. Sem internet | Slides com as evidências; o código no GitHub fica para a avaliação |

**Nunca apresentar com a API fria.** Medido em 03/11: depois de a API ficar
parada, a primeira requisição levou cerca de um minuto, porque o container sobe e
carrega o TensorFlow. O `demo/preparar.sh` deixa uma instância ligada e faz uma
requisição de aquecimento.

O gerador em segundo plano sobrevive ao fechamento da aba, mas não ao
encerramento da máquina do Cloud Shell, que tem limites de sessão e de
inatividade. Mantenha a aba do `tail -f` aberta até o fim.

## Custos do dia

Estimativas, para cerca de 2 horas ligadas:
- **Dataflow** (1 worker): na casa de US$ 0,50.
- **Instância fixa do Cloud Run:** centavos.
- **Pub/Sub e BigQuery:** centavos.

O `infra/teardown.sh` desliga o que cobra por hora, e não apaga dados.
