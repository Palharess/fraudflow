-- ###########################################################################
-- ROTEIRO DA DEMONSTRAÇÃO AO VIVO — Trabalho 1
--
-- Abra cada bloco em uma ABA SEPARADA do editor do BigQuery, já colado e
-- pronto para clicar em "Executar". Sob pressão de tempo, digitar é o que
-- mais custa minutos.
--
-- Todas as consultas leem tabelas que JÁ EXISTEM. Nenhuma reconstrói nada:
-- o pipeline está em produção, e é isso que o enunciado pede demonstrar.
--
-- Tempo alvo: 2min40 com as cinco. Cortando o bloco 4, cai para 2min.
-- ###########################################################################


-- ===========================================================================
-- [1 · OBRIGATORIA] BRONZE — o espelho fiel do arquivo
--
-- FALA: "A Bronze não transforma nada: todos os campos como texto, exatamente
--        como vieram do CSV. O que ela acrescenta é linhagem."
-- APONTAR: source_file registra a origem de cada linha, e mostra só
--          raw/train — o conjunto de teste ficou fora do BigQuery de
--          propósito, lacrado no Cloud Storage para o Trabalho 2.
-- ===========================================================================
SELECT
  trans_date_trans_time,
  amt,
  merchant,
  is_fraud,
  source_file
FROM `fraudflow-pdm-gps.bronze.transactions`
LIMIT 5;


-- ===========================================================================
-- [2 · OBRIGATORIA] SILVER — limpeza provada por numero
--
-- FALA: "Em vez de afirmar que a camada ficou limpa, nós medimos."
-- APONTAR: zero duplicatas, zero prefixo remanescente, e a janela terminando
--          em 21 de junho de 2020 — prova de que o holdout não vazou.
-- ===========================================================================
SELECT
  COUNT(*)                                          AS linhas,
  COUNTIF(is_fraud = 1)                             AS fraudes,
  ROUND(100 * COUNTIF(is_fraud = 1) / COUNT(*), 3)  AS pct_fraude,
  COUNT(*) - COUNT(DISTINCT transaction_id)         AS duplicatas,
  COUNTIF(STARTS_WITH(merchant_name, 'fraud_'))     AS prefixo_restante,
  MIN(transaction_ts)                               AS primeira_transacao,
  MAX(transaction_ts)                               AS ultima_transacao
FROM `fraudflow-pdm-gps.silver.transactions`;


-- ===========================================================================
-- [3 · OBRIGATORIA] GOLD — a camada de inteligencia de negocio
--
-- FALA: "A Gold tem duas saídas. Esta é a de BI: 1,3 milhão de transações
--        viram 12 mil linhas agregadas. As categorias online concentram a
--        fraude — guarde esse padrão, porque o modelo vai reencontrá-lo."
-- ===========================================================================
SELECT
  category                                                       AS categoria,
  SUM(transactions)                                              AS transacoes,
  SUM(frauds)                                                    AS fraudes,
  ROUND(100 * SAFE_DIVIDE(SUM(frauds), SUM(transactions)), 3)    AS pct_fraude
FROM `fraudflow-pdm-gps.gold.fraud_analytics`
GROUP BY categoria
ORDER BY pct_fraude DESC
LIMIT 6;


-- ===========================================================================
-- [4 · A SINTESE — corte esta se o relogio apertar] As tres camadas lado a lado
--                                                                   (~40 s)
--
-- SINTESE. Vem depois das tres camadas de proposito: a essa altura o professor
-- ja sabe o que cada uma faz, entao ver as tres juntas REFORCA em vez de
-- introduzir. E a ultima linha e a Gold, que e exatamente o que o modelo
-- consome — o que emenda direto na inferencia do bloco 5.
--
-- Se o relogio apertar, CORTE ESTA. E a unica que o enunciado nao exige.
--
-- FALA: "Vimos as tres camadas separadas. Agora as tres juntas: peguei uma
--        fraude real e segui ela pelo pipeline. Repare o texto virando
--        TIMESTAMP de verdade, o valor virando numero, o prefixo 'fraud_'
--        saindo — e a ultima linha, que e o contrato do modelo, ja sem o
--        comerciante."
-- EMENDAR: "...e e exatamente essa linha que o modelo recebe agora."
-- ===========================================================================
WITH alvo AS (
  -- A fraude mais recente da base. Determinístico: sempre a mesma linha.
  SELECT transaction_id
  FROM `fraudflow-pdm-gps.gold.ml_input`
  WHERE is_fraud = 1
  ORDER BY transaction_ts DESC
  LIMIT 1
)

SELECT '1 · BRONZE — cru'        AS camada,
       b.trans_date_trans_time   AS tempo,
       b.amt                     AS valor,
       b.merchant                AS comerciante,
       b.dob                     AS nascimento
FROM `fraudflow-pdm-gps.bronze.transactions` AS b
JOIN alvo ON b.trans_num = alvo.transaction_id

UNION ALL
SELECT '2 · SILVER — limpo',
       CAST(s.transaction_ts AS STRING),
       CAST(s.amount AS STRING),
       s.merchant_name,
       CAST(s.customer_dob AS STRING)
FROM `fraudflow-pdm-gps.silver.transactions` AS s
JOIN alvo USING (transaction_id)

UNION ALL
SELECT '3 · GOLD — contrato do modelo',
       CAST(g.transaction_ts AS STRING),
       CAST(g.amount AS STRING),
       '(fora do contrato)',
       CAST(g.customer_dob AS STRING)
FROM `fraudflow-pdm-gps.gold.ml_input` AS g
JOIN alvo USING (transaction_id)

ORDER BY camada;


-- ===========================================================================
-- [5 · OBRIGATORIA] BIGQUERY ML — a inferencia ao vivo
--
-- FALA: "O modelo recebe apenas os campos do contrato — sem o rótulo. Ele
--        pontua cada transação, e só DEPOIS da inferência trazemos a
--        resposta verdadeira por um JOIN, para mostrar acerto e erro.
--        É a mesma separação que a API do Trabalho 2 vai ter."
-- APONTAR: o filtro por data usa o particionamento e lê uma única partição.
--          Este é o período de validação, que o modelo não viu no treino.
-- ===========================================================================
WITH evento AS (
  -- Só os campos do contrato. Nenhum rótulo passa por aqui.
  SELECT
    transaction_id, transaction_ts, customer_dob,
    customer_lat, customer_long, merchant_lat, merchant_long,
    amount, category, city_pop
  FROM `fraudflow-pdm-gps.gold.ml_input`
  WHERE DATE(transaction_ts) = '2020-06-20'
),

pontuado AS (
  SELECT
    transaction_id,
    transaction_ts,
    amount,
    category,
    (SELECT p.prob
     FROM UNNEST(predicted_is_fraud_probs) AS p
     WHERE CAST(p.label AS STRING) = '1')  AS fraud_score
  FROM ML.PREDICT(
         MODEL `fraudflow-pdm-gps.gold.fraud_boosted`,
         (SELECT * FROM evento))
)

-- O rótulo verdadeiro só encosta na predição AGORA.
SELECT
  FORMAT_TIMESTAMP('%d/%m %H:%M', p.transaction_ts)           AS quando,
  p.category                                                  AS categoria,
  ROUND(p.amount, 2)                                          AS valor,
  ROUND(p.fraud_score, 4)                                     AS fraud_score,
  IF(p.fraud_score >= 0.5, 'FRAUDE', 'legitima')              AS decisao,
  r.is_fraud                                                  AS rotulo_real,
  IF((p.fraud_score >= 0.5) = (r.is_fraud = 1), 'ok', 'ERRO') AS resultado
FROM pontuado AS p
JOIN `fraudflow-pdm-gps.gold.ml_input` AS r USING (transaction_id)
ORDER BY p.fraud_score DESC
LIMIT 10;


-- ###########################################################################
-- DAQUI PARA BAIXO: reserva. Só se o relógio permitir.
-- ###########################################################################


-- ===========================================================================
-- [6 · RESERVA] Métricas dos dois modelos                         (~25 s)
--
-- FALA: "Com fraude em 0,58% dos casos, acurácia não diz nada — responder
--        'não é fraude' sempre já acerta 99,4%, mais que o nosso modelo.
--        A leitura correta é por recall e precision."
-- ===========================================================================
SELECT 'v1 · logistica'    AS modelo,
       ROUND(recall, 4)    AS recall,
       ROUND(precision, 4) AS precision,
       ROUND(f1_score, 4)  AS f1,
       ROUND(roc_auc, 4)   AS roc_auc
FROM ML.EVALUATE(MODEL `fraudflow-pdm-gps.gold.fraud_logistic`)
UNION ALL
SELECT 'v2 · boosted tree',
       ROUND(recall, 4), ROUND(precision, 4), ROUND(f1_score, 4), ROUND(roc_auc, 4)
FROM ML.EVALUATE(MODEL `fraudflow-pdm-gps.gold.fraud_boosted`)
ORDER BY modelo;


-- ===========================================================================
-- [7 · RESERVA] O que o modelo achou importante                   (~20 s)
--
-- FALA: "O modelo elegeu 'is_night' como a feature mais decisiva, com folga
--        de mais de três vezes sobre a segunda. É exatamente o padrão que a
--        Gold mostrou: a madrugada tem 18 vezes mais fraude. O modelo
--        redescobriu sozinho o que os dados já diziam."
-- ===========================================================================
SELECT
  feature,
  ROUND(importance_gain, 2) AS ganho
FROM ML.FEATURE_IMPORTANCE(MODEL `fraudflow-pdm-gps.gold.fraud_boosted`)
ORDER BY ganho DESC;


-- ===========================================================================
-- [8 · RESERVA — SÓ SE ELE PEDIR] Reconstruir uma camada ao vivo  (~15 s)
--
-- Prova que o pipeline é reproduzível e idempotente. É a única consulta que
-- ESCREVE. Roda em segundos: lê a Silver e grava 12 mil linhas.
-- NÃO rode por iniciativa própria se estiver perto do limite de tempo.
--
-- O conteúdo está em sql/gold/21_gold_fraud_analytics.sql
-- ===========================================================================
