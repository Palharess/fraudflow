-- ===========================================================================
-- Camada Bronze - materializacao com metadados de governanca
--
-- A carga do CSV cru (GCS -> bronze.transactions_stg) e um LOAD JOB do
-- BigQuery, gratuito e sem SQL, disparado pelo notebook 01. Este script e o
-- passo seguinte: acrescenta ingestion_timestamp e source_file, que registram
-- de qual arquivo cada linha veio.
--
-- SEM particionamento, de proposito: a carga acontece de uma vez so, entao
-- particionar por data de ingestao criaria uma unica particao.
-- ===========================================================================

CREATE OR REPLACE TABLE `${PROJECT_ID}.bronze.transactions` AS
SELECT
  s.*,
  CURRENT_TIMESTAMP() AS ingestion_timestamp,
  'gs://${BUCKET_NAME}/raw/train/fraudTrain.csv'         AS source_file
FROM `${PROJECT_ID}.bronze.transactions_stg` AS s
