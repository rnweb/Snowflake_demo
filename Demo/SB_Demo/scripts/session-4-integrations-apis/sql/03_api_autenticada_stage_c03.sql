-- =============================================================================
-- Session 4 (C03) — 03: Authenticated external API -> stage -> working table
-- =============================================================================
-- C03-AE-02: "Consumir una API de data externa autenticada e ingerir su respuesta
-- en una tabla de trabajo." Criterion: the response is captured, turned into a
-- tabular / semi-structured structure and is queryable.
--
-- Why not 01_api_ingestion_procedure.sql: the trial account blocks External
-- Access Integrations (509009), so Snowflake cannot call the API itself.
-- Pattern used here (works on trial, no cloud credentials exchanged):
--   1. The API call is made OUTSIDE Snowflake, authenticated with an API key kept
--      in an environment variable (powershell/fx_api_autenticada.ps1):
--      ExchangeRate-API v6, base USD, includes DOP (peso dominicano).
--   2. The JSON response lands in an INTERNAL named stage (upload from Snowsight
--      or PUT) — governed storage inside Snowflake, no bucket keys to share.
--   3. COPY INTO a VARIANT table (semi-structured, full payload kept for audit).
--   4. A view flattens it into rows (moneda, tasa) for SQL / BI.
-- Production variant: same COPY from an EXTERNAL stage on Azure Blob Storage
-- through a STORAGE INTEGRATION (no keys in SQL), or the Snowpark procedure of
-- 01_api_ingestion_procedure.sql once External Access is allowed.
--
-- Run as FR_DATA_ENGINEER (has build rights on STAGING_SCHEMA). Idempotent.
-- =============================================================================
USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_INGESTION_MEDIUM;
USE SCHEMA SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA;

-- -----------------------------------------------------------------------------
-- 1. Landing objects (run once, before the demo)
-- -----------------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS FF_JSON_API
  TYPE = JSON STRIP_OUTER_ARRAY = FALSE
  COMMENT = 'C03-AE-02: respuestas JSON de APIs externas';

CREATE STAGE IF NOT EXISTS API_LANDING_STAGE
  FILE_FORMAT = FF_JSON_API
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'C03-AE-02: aterrizaje de respuestas de APIs externas (stage interno, cifrado por Snowflake)';

CREATE TABLE IF NOT EXISTS API_TIPO_CAMBIO_RAW (
    ARCHIVO      VARCHAR        COMMENT 'Archivo de origen en el stage (trazabilidad)',
    CARGADO_EN   TIMESTAMP_LTZ  COMMENT 'Momento de la ingesta',
    PAYLOAD      VARIANT        COMMENT 'Respuesta completa de la API (sin transformar)'
) COMMENT = 'C03-AE-02: respuestas crudas de ExchangeRate-API (capa Bronce)';

-- -----------------------------------------------------------------------------
-- 2. DEMO — after uploading the JSON file to the stage
--    (Snowsight: Data > STAGING_SCHEMA > Stages > API_LANDING_STAGE > + Files)
-- -----------------------------------------------------------------------------
LIST @API_LANDING_STAGE;

-- Peek at the raw response before loading
SELECT $1:result::STRING AS RESULTADO, $1:base_code::STRING AS BASE,
       $1:time_last_update_utc::STRING AS ACTUALIZADO, $1:conversion_rates:DOP AS USD_DOP
FROM @API_LANDING_STAGE (FILE_FORMAT => 'FF_JSON_API');

-- Ingest (COPY skips files already loaded: re-running is safe)
COPY INTO API_TIPO_CAMBIO_RAW (ARCHIVO, CARGADO_EN, PAYLOAD)
FROM (SELECT METADATA$FILENAME, CURRENT_TIMESTAMP(), $1 FROM @API_LANDING_STAGE)
FILE_FORMAT = (FORMAT_NAME = 'FF_JSON_API')
PATTERN = '.*tipo_cambio_.*';     -- matches .json and .json.gz (auto-compressed uploads)

-- -----------------------------------------------------------------------------
-- 3. Tabular view (Plata): one row per currency per load
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_TIPO_CAMBIO
  COMMENT = 'C03-AE-02: tipo de cambio por moneda (aplanado desde la respuesta JSON de la API)'
AS
SELECT r.ARCHIVO,
       r.CARGADO_EN,
       r.PAYLOAD:base_code::STRING                         AS MONEDA_BASE,
       TRY_TO_TIMESTAMP_TZ(r.PAYLOAD:time_last_update_utc::STRING,
                           'DY, DD MON YYYY HH24:MI:SS TZHTZM') AS FECHA_TASA,
       f.key::STRING                                       AS MONEDA,
       f.value::NUMBER(18,6)                               AS TASA
FROM API_TIPO_CAMBIO_RAW r,
     LATERAL FLATTEN(INPUT => r.PAYLOAD:conversion_rates) f
WHERE r.PAYLOAD:result::STRING = 'success';

-- Result for the demo: the currencies that matter to the Superintendencia
SELECT MONEDA_BASE, MONEDA, TASA, FECHA_TASA, CARGADO_EN, ARCHIVO
FROM VW_TIPO_CAMBIO
WHERE MONEDA IN ('DOP', 'EUR', 'MXN', 'BRL', 'CLP')
ORDER BY CARGADO_EN DESC, MONEDA;

-- Audit trail of the load
SELECT FILE_NAME, STATUS, ROW_COUNT, LAST_LOAD_TIME
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.API_TIPO_CAMBIO_RAW',
       START_TIME => DATEADD('day', -1, CURRENT_TIMESTAMP())));
