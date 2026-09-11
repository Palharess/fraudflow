-- ===========================================================================
-- Avaliacao dos modelos
--
-- Com fraude em 0,58% dos casos a acuracia nao e informativa: responder
-- 'nao e fraude' para tudo ja acerta 99,4%. A leitura correta e por recall,
-- precision e F1, com a matriz de confusao ao lado.
-- ===========================================================================

SELECT 'v1 · logistica' AS modelo,
           ROUND(recall, 4) AS recall, ROUND(precision, 4) AS precision,
           ROUND(f1_score, 4) AS f1, ROUND(roc_auc, 4) AS roc_auc,
           ROUND(accuracy, 4) AS accuracy
    FROM ML.EVALUATE(MODEL `${PROJECT_ID}.gold.fraud_logistic`)
    UNION ALL
    SELECT 'v2 · boosted tree',
           ROUND(recall, 4), ROUND(precision, 4), ROUND(f1_score, 4),
           ROUND(roc_auc, 4), ROUND(accuracy, 4)
    FROM ML.EVALUATE(MODEL `${PROJECT_ID}.gold.fraud_boosted`)
    ORDER BY modelo

-- ------------------------------------------------------------------------

SELECT * FROM ML.CONFUSION_MATRIX(MODEL `${PROJECT_ID}.gold.fraud_boosted`)

-- ------------------------------------------------------------------------

SELECT feature,
           ROUND(importance_gain, 5)   AS ganho,
           ROUND(importance_weight, 5) AS peso,
           ROUND(importance_cover, 5)  AS cobertura
    FROM ML.FEATURE_IMPORTANCE(MODEL `${PROJECT_ID}.gold.fraud_boosted`)
    ORDER BY ganho DESC

-- ------------------------------------------------------------------------

SELECT processed_input AS feature, ROUND(weight, 5) AS peso
    FROM ML.WEIGHTS(MODEL `${PROJECT_ID}.gold.fraud_logistic`)
    WHERE weight IS NOT NULL
    ORDER BY ABS(weight) DESC
    LIMIT 20
