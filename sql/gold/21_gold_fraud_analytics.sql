-- ===========================================================================
-- 21 · gold.fraud_analytics
--
-- Camada de inteligência de negócio: agregados de fraude por categoria, hora
-- e estado. É o que o Looker Studio consome e o que vira slide.
--
-- Não alimenta o modelo. Aqui as agregações são livres, porque nada daqui
-- entra no TRANSFORM.
-- ===========================================================================

CREATE OR REPLACE TABLE `${PROJECT_ID}.gold.fraud_analytics` AS
SELECT
  category,
  EXTRACT(HOUR FROM transaction_ts)                        AS hour,
  customer_state,
  transaction_date,

  COUNT(*)                                                 AS transactions,
  COUNTIF(is_fraud = 1)                                    AS frauds,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_fraud = 1), COUNT(*)), 4)
                                                           AS fraud_rate_pct,
  ROUND(SUM(amount), 2)                                    AS total_amount,
  ROUND(SUM(IF(is_fraud = 1, amount, 0)), 2)               AS fraud_amount,
  ROUND(AVG(amount), 2)                                    AS avg_ticket,
  ROUND(AVG(IF(is_fraud = 1, amount, NULL)), 2)            AS avg_ticket_fraud
FROM `${PROJECT_ID}.silver.transactions`
GROUP BY category, hour, customer_state, transaction_date;


-- ---------------------------------------------------------------------------
-- Os dois números que o plano manda levar para o slide de honestidade:
-- as separações do simulador são limpas demais para fraude real, e é melhor
-- sermos nós a explicar isso antes que alguém pergunte.
-- ---------------------------------------------------------------------------

-- Madrugada contra o resto do dia
SELECT
  IF(hour >= 22 OR hour <= 3, 'madrugada (22h-3h)', 'resto do dia') AS periodo,
  SUM(transactions)                                             AS transacoes,
  SUM(frauds)                                                   AS fraudes,
  ROUND(100 * SAFE_DIVIDE(SUM(frauds), SUM(transactions)), 4)   AS pct_fraude
FROM `${PROJECT_ID}.gold.fraud_analytics`
GROUP BY periodo
ORDER BY pct_fraude DESC;

-- Taxa de fraude por faixa de valor
SELECT
  CASE
    WHEN amount <  50   THEN 'a. ate 50'
    WHEN amount <  200  THEN 'b. 50 a 200'
    WHEN amount <  500  THEN 'c. 200 a 500'
    WHEN amount < 1000  THEN 'd. 500 a 1000'
    ELSE                     'e. acima de 1000'
  END                                                       AS faixa_valor,
  COUNT(*)                                                  AS transacoes,
  COUNTIF(is_fraud = 1)                                     AS fraudes,
  ROUND(100 * COUNTIF(is_fraud = 1) / COUNT(*), 4)          AS pct_fraude
FROM `${PROJECT_ID}.silver.transactions`
GROUP BY faixa_valor
ORDER BY faixa_valor;
