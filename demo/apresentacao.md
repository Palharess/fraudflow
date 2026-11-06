# Apresentação do Trabalho 2 · sexta, 06/11/2026

Guia direto do que rodar e do que mostrar. Limite de **10 minutos**; a meta é
**9 minutos**, com cronômetro visível.

| Fase | Quando | Duração |
|---|---|---|
| 1. Preparar | 1 hora antes | ~20 min |
| 2. Slides | início | ~4 min |
| 3. Demo ao vivo | logo depois dos slides | ~5 min |
| 4. Desligar | depois | 5 min |

Tudo roda no **Cloud Shell** do projeto `fraudflow-pdm-gps`.

---

## 1. Preparar (antes da apresentação)

**1 hora antes:** ligar a API e o Dataflow.

1. Atualize o repositório e ative o ambiente do Beam:
```bash
cd ~/fraudflow && git pull && source ~/venv-beam/bin/activate
```

2. Rode a preparação. Ela termina mostrando `JOB_STATE_RUNNING`:
```bash
bash demo/preparar.sh
```

**45 minutos antes:** no console, abra **Dataflow → fraudflow-stream** e espere
aparecer **1 worker atual**. Se em 15 minutos não houver worker, use o plano B 1.

**30 minutos antes:** ligar o gerador. São **dois comandos separados**.

1. Entre na pasta do projeto:
```bash
cd ~/fraudflow
```

2. Ligue o gerador:
```bash
nohup ~/venv-gerador/bin/python producer/publisher.py --inicio 14138 --taxa 5 --invalidos 60 --intervalo-invalidos 300 > ~/gerador.log 2>&1 &
```

**28 minutos antes:** conferir que tudo funciona.
```bash
bash demo/conferir.sh
```

O esperado:
- gerador **rodando**;
- job **JOB_STATE_RUNNING**;
- `validas_5min` com algumas centenas;
- `erros_5min` em 1 ou mais;
- API respondendo **200** em menos de 1 s.

**15 minutos antes:** abrir as abas, nesta ordem.

1. **Slides**, em modo apresentação.
2. **Cloud Shell, aba 1**, com o gerador ao vivo:
```bash
tail -f ~/gerador.log
```
3. **Cloud Shell, aba 2**, livre, em `~/fraudflow`.
4. **Dataflow** → `fraudflow-stream`, no grafo.
5. **BigQuery**, com cinco abas, cada uma com uma consulta já colada: **B, A, 1, 2, 3** (fim deste arquivo).
6. **API**: https://fraudflow-api-189235868606.us-central1.run.app/docs

Aumente o zoom do navegador (`Ctrl` + `+`) e a fonte do Cloud Shell.

**5 minutos antes:** rode `bash demo/conferir.sh` de novo.

---

## 2. Slides (~4 min)

As falas completas estão nas notas de cada slide.

| Slide | Tempo | Ideia central |
|---|---|---|
| 1 · Capa | 0:30 | Detecção de fraude em cartão. T1: histórico em lote e modelo. T2: tempo real e API. Três camadas: batch, streaming e serviço |
| 2 · Arquitetura | 1:00 | Azul: batch (Bronze, Silver, Gold, modelo). Verde: streaming (gerador, Pub/Sub, Dataflow). A view junta os dois. Laranja: modelo dentro da API no Cloud Run |
| 3 · Caminho de uma transação | 0:30 | Gerador → fila → Dataflow → BigQuery → view. O stream continua de onde o histórico parou. A API funciona em paralelo |
| 4 · Decisões | 0:45 | Partição por data, horário original da compra, duplicatas em duas camadas, erros registrados |
| 5 · Problemas e caminhos | 1:00 | Vertex AI sem máquina → modelo dentro da API (Docker), com contingência pelo ML.PREDICT. Dataflow sem máquina → troca o tipo. O teste de paridade pegou um erro silencioso |
| 6 · Resultados | 0:30 | 97 de cada 100 fraudes, o mesmo resultado fora do BigQuery, API em 51 ms. **"Agora vamos ver funcionando."** |

---

## 3. Demo ao vivo (~5 min)

Tudo já está rodando: só trocar de aba e executar.

### Batch · 0:45 · BigQuery

| Fazer | Dizer |
|---|---|
| Executar a **consulta B** | "A regra da Silver em 5 linhas da Bronze: o texto vira horário e número, e o prefixo `fraud_` sai." |
| Executar a **consulta A** | "1.296.675 transações da Bronze à Gold. É desse histórico que sai o modelo." |

### Streaming · 2:30 · Cloud Shell, Dataflow e BigQuery

| Fazer | Dizer |
|---|---|
| **Cloud Shell, aba 1** (o `tail -f`) | "O gerador publicando agora, 5 transações por segundo, no Pub/Sub." |
| **Dataflow**, o grafo | "O Dataflow lê a fila, aplica as regras da Silver e separa válidas e erros." |
| Executar a **consulta 1** | "Na mesma visão: batch é o histórico; stream, o que está chegando agora." |
| Executar a **consulta 2** | "As últimas transações que entraram na Silver de streaming: a compra é de 2020, o horário original, mas chegou há segundos. Os campos já estão limpos." |
| Executar a **consulta 3** | "Um evento inválido por minuto. Não derruba o pipeline: fica registrado com o motivo." |
| Executar a **consulta 2** e a **1** de novo | "Transações novas no topo, e o stream cresceu. O batch continua igual." |

### API · 1:30 · Cloud Shell, aba 2, e /docs

1. Rode o teste da API:
```bash
python3 demo/testar_api.py
```

| O que aparece | Dizer |
|---|---|
| 1ª: `fraud_score` ~0,95 e rótulo **FRAUDE** | "Score alto. Só depois da resposta revelamos que era fraude." |
| 2ª: `fraud_score` ~0,04 e rótulo **legítima** | "Score baixo: legítima. A inferência levou poucos milissegundos." |
| 3ª: erro **422** | "Entrada inválida: a API recusa e explica cada campo." |

2. Abra o **/docs**: "O contrato da API, gerado automaticamente."

### Fechamento · 0:15

> "O código, o README e as evidências estão no GitHub. No Trabalho Final, o
> Dataflow vai chamar esta API para cada transação."

---

## 4. Desligar (depois da apresentação)

1. Pare o gerador:
```bash
pkill -INT -f producer/publisher.py
```

2. Veja o resumo e anote o `--inicio` da linha "Para continuar", que é o da próxima vez:
```bash
tail -n 4 ~/gerador.log
```

3. Desligue o que cobra por hora:
```bash
cd ~/fraudflow && bash infra/teardown.sh
```

4. No console do Dataflow, confira o job como **Reduzido** (*Drained*).

---

## Plano B

| Se acontecer | Fazer |
|---|---|
| Dataflow sem worker depois de 15 min | Com o ambiente do Beam ativo: `MAQUINA=e2-standard-2 bash demo/reiniciar_dataflow.sh` |
| O gerador parou | `bash demo/conferir.sh` mostra. Ligar de novo com o `--inicio` da última linha "Para continuar" do log |
| A API principal lenta ou fora | `python3 demo/testar_api.py --contingencia`: o mesmo score, pelo ML.PREDICT |
| O professor pergunta da emenda ou da latência | Consultas extras no fim do `demo/README.md` |

**Nunca apresentar com a API fria:** o `preparar.sh` já deixa uma instância
ligada e aquecida.

---

## Consultas (colar no BigQuery antes de começar)

**B · A transformação da Silver**
```sql
SELECT
  trans_date_trans_time, amt, merchant,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%S', trans_date_trans_time) AS transaction_ts,
  SAFE_CAST(amt AS FLOAT64)                                        AS amount,
  REGEXP_REPLACE(merchant, r'^fraud_', '')                         AS merchant_name
FROM `fraudflow-pdm-gps.bronze.transactions`
LIMIT 5;
```

**A · Volume em cada camada do batch**
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

**2 · Últimas transações que chegaram na Silver de streaming**
```sql
SELECT
  FORMAT_TIMESTAMP('%H:%M:%S', processed_at, 'America/Sao_Paulo') AS chegou_as,
  FORMAT_TIMESTAMP('%d/%m/%Y %H:%M', transaction_ts)               AS horario_da_compra,
  category, ROUND(amount, 2) AS valor, merchant_name, customer_state
FROM `fraudflow-pdm-gps.silver.transactions_stream`
WHERE processed_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
ORDER BY processed_at DESC
LIMIT 10;
```

**3 · Erros por motivo (hoje)**
```sql
SELECT error_reason, COUNT(*) AS eventos, MAX(processed_at) AS ultimo
FROM `fraudflow-pdm-gps.silver.transactions_stream_errors`
WHERE DATE(processed_at) = CURRENT_DATE()
GROUP BY error_reason ORDER BY eventos DESC;
```
