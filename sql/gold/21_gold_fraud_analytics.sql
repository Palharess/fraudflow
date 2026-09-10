-- ===========================================================================
-- 21 · gold.fraud_analytics
--
-- Camada de inteligência de negócio: agregados de fraude por categoria, hora
-- e estado. E o que o Looker Studio consome e o que vira slide.
--
-- SEM a data no GROUP BY, de proposito: com ~2.400 transacoes por dia para
-- 17.136 combinacoes possiveis, agrupar por dia deixaria quase uma linha por
-- transacao e a taxa de fraude viraria 0% ou 100%. Sem a data, sao no maximo
-- 17.136 linhas com ~76 transacoes cada, e a taxa passa a ter significado.
--
-- Não alimenta o modelo. Aqui as agregações são livres, porque nada daqui
-- entra no TRANSFORM.
-- ===========================================================================

CREATE OR REPLACE TABLE `${PROJECT_ID}.gold.fraud_analytics` AS
SELECT
  category,
  EXTRACT(HOUR FROM transaction_ts)                        AS hour,
  customer_state,

  COUNT(*)                                                 AS transactions,
  COUNTIF(is_fraud = 1)                                    AS frauds,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_fraud = 1), COUNT(*)), 4)
                                                           AS fraud_rate_pct,
  ROUND(SUM(amount), 2)                                    AS total_amount,
  ROUND(SUM(IF(is_fraud = 1, amount, 0)), 2)               AS fraud_amount,
  ROUND(AVG(amount), 2)                                    AS avg_ticket,
  ROUND(AVG(IF(is_fraud = 1, amount, NULL)), 2)            AS avg_ticket_fraud
FROM `${PROJECT_ID}.silver.transactions`
GROUP BY category, hour, customer_state;
