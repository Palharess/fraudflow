-- ===========================================================================
-- 32 · Avaliação
--
-- Com fraude em 0,5% dos casos, acurácia não diz nada: um modelo que responde
-- "não é fraude" para tudo acerta 99,5%. O slide de resultados lidera com
-- recall, precision e F1, com a matriz de confusão visível. ROC-AUC entra
-- como métrica complementar, nunca como manchete.
--
-- Rode UMA CONSULTA POR VEZ no editor do BigQuery: são blocos independentes.
-- ===========================================================================

-- 1) v1 contra v2, lado a lado, no recorte de validação reservado pelo SEQ.
SELECT 'v1 · logistica'  AS modelo,
       ROUND(recall,    4) AS recall,
       ROUND(precision, 4) AS precision,
       ROUND(f1_score,  4) AS f1,
       ROUND(roc_auc,   4) AS roc_auc,
       ROUND(accuracy,  4) AS accuracy
FROM ML.EVALUATE(MODEL `${PROJECT_ID}.gold.fraud_logistic`)
UNION ALL
SELECT 'v2 · boosted tree',
       ROUND(recall, 4), ROUND(precision, 4), ROUND(f1_score, 4),
       ROUND(roc_auc, 4), ROUND(accuracy, 4)
FROM ML.EVALUATE(MODEL `${PROJECT_ID}.gold.fraud_boosted`)
ORDER BY modelo;


-- 2) Matriz de confusão do modelo escolhido.
--    Falso negativo = fraude que passou. Falso positivo = cliente legítimo
--    bloqueado. Custam coisas diferentes, e é isso que o limiar decide.
SELECT * FROM ML.CONFUSION_MATRIX(MODEL `${PROJECT_ID}.gold.fraud_boosted`);


-- 3) Escolha do limiar, no recorte de validação.
--    A saída do T1 é um fraud_score mais um único limiar, resultando em
--    FRAUD ou LEGIT. As três faixas — aprovar, revisar, bloquear — ficam
--    para o Trabalho 2.
WITH validacao AS (
  SELECT * EXCEPT (transaction_id, split_key)
  FROM `${PROJECT_ID}.gold.ml_input`
  WHERE transaction_ts >= (
    SELECT APPROX_QUANTILES(transaction_ts, 5)[OFFSET(4)]
    FROM `${PROJECT_ID}.gold.ml_input`
  )
)
SELECT 0.50 AS limiar, ROUND(recall,4) AS recall,
       ROUND(precision,4) AS precision, ROUND(f1_score,4) AS f1
FROM ML.EVALUATE(MODEL `${PROJECT_ID}.gold.fraud_boosted`,
                 (SELECT * FROM validacao), STRUCT(0.50 AS threshold))
UNION ALL
SELECT 0.30, ROUND(recall,4), ROUND(precision,4), ROUND(f1_score,4)
FROM ML.EVALUATE(MODEL `${PROJECT_ID}.gold.fraud_boosted`,
                 (SELECT * FROM validacao), STRUCT(0.30 AS threshold))
UNION ALL
SELECT 0.15, ROUND(recall,4), ROUND(precision,4), ROUND(f1_score,4)
FROM ML.EVALUATE(MODEL `${PROJECT_ID}.gold.fraud_boosted`,
                 (SELECT * FROM validacao), STRUCT(0.15 AS threshold))
ORDER BY limiar DESC;


-- 4) Peso de cada feature no modelo v2.
--    Serve para conferir se as nove features do TRANSFORM estão fazendo
--    alguma coisa, e quais são realmente decisivas.
SELECT
  feature,
  ROUND(importance_gain,   5) AS ganho,
  ROUND(importance_weight, 5) AS peso,
  ROUND(importance_cover,  5) AS cobertura
FROM ML.FEATURE_IMPORTANCE(MODEL `${PROJECT_ID}.gold.fraud_boosted`)
ORDER BY ganho DESC;


-- 5) Coeficientes do v1. A logística permite ler a direção de cada efeito,
--    coisa que a árvore não dá — bom para explicar o modelo em uma frase.
SELECT
  processed_input                         AS feature,
  ROUND(weight, 5)                        AS peso
FROM ML.WEIGHTS(MODEL `${PROJECT_ID}.gold.fraud_logistic`)
WHERE weight IS NOT NULL
ORDER BY ABS(weight) DESC
LIMIT 20;
