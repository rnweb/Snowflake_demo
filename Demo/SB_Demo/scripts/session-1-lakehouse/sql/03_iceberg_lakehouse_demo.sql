-- =============================================================================
-- Session 1 — 03: Apache Iceberg lakehouse demo (open table format)
-- =============================================================================
-- Rol: FR_DATA_ENGINEER | Almacén: WH_INGESTION_XSMALL
--
-- Purpose: prove that Snowflake acts as a true Data Lakehouse over OPEN
-- formats — the same Parquet files on an internal stage remain readable by
-- any Iceberg-compatible engine (Athena, Spark, Flink, Dremio...), so the
-- regulator's data is never locked into a proprietary format.
--
-- Steps:
--   1. Internal stage for the demo (self-contained)
--   2. Export the credit-card history as PARQUET files onto the stage
--   3. CREATE ICEBERG TABLE HISTORICO_TRANSACCIONES_ICEBERG (Snowflake-managed
--      catalog — open Apache Iceberg spec, Parquet data files)
--   4. Load history into the Iceberg table
--   5. Verify: row counts, sample rows and the physical Parquet files
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Internal stage backing the Iceberg demo (self-contained)
-- -----------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS STAGING_SCHEMA.ICEBERG_DEMO_STAGE
  COMMENT = 'Internal stage for the Apache Iceberg lakehouse demo (open formats).';

-- -----------------------------------------------------------------------------
-- 2. Export history as PARQUET on the internal stage (open format artifact)
-- -----------------------------------------------------------------------------
COPY INTO @STAGING_SCHEMA.ICEBERG_DEMO_STAGE/historico_transacciones/
FROM (
    SELECT
        ID_TRANSACCION,
        RUT,
        NUMERO_TARJETA,
        FECHA_TRANSACCION,
        MONTO,
        CATEGORIA,
        COMERCIO,
        CIUDAD,
        ESTADO,
        UNIDAD_NEGOCIO
    FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
)
FILE_FORMAT = (TYPE = PARQUET)
OVERWRITE = TRUE;

-- -----------------------------------------------------------------------------
-- 3. Iceberg table (open Apache Iceberg spec, Snowflake-managed storage)
-- -----------------------------------------------------------------------------
CREATE ICEBERG TABLE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.HISTORICO_TRANSACCIONES_ICEBERG (
    ID_TRANSACCION    STRING,
    RUT               STRING,
    NUMERO_TARJETA    STRING,
    FECHA_TRANSACCION TIMESTAMP_NTZ,
    MONTO             NUMBER(14, 2),
    CATEGORIA         STRING,
    COMERCIO          STRING,
    CIUDAD            STRING,
    ESTADO            STRING,
    UNIDAD_NEGOCIO    STRING
)
CATALOG = 'SNOWFLAKE'
COMMENT = 'Historico de transacciones en formato Apache Iceberg (Parquet) — prueba de lakehouse abierto, sin vendor lock-in.';

-- -----------------------------------------------------------------------------
-- 4. Load the full history (Iceberg writes Parquet data files + metadata)
-- -----------------------------------------------------------------------------
-- Re-runs stay clean: truncate before reloading.
TRUNCATE TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.HISTORICO_TRANSACCIONES_ICEBERG;

INSERT INTO SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.HISTORICO_TRANSACCIONES_ICEBERG
SELECT
    ID_TRANSACCION,
    RUT,
    NUMERO_TARJETA,
    FECHA_TRANSACCION,
    MONTO,
    CATEGORIA,
    COMERCIO,
    CIUDAD,
    ESTADO,
    UNIDAD_NEGOCIO
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS;

-- -----------------------------------------------------------------------------
-- 5. Verification
-- -----------------------------------------------------------------------------
-- 5a. The table is registered as ICEBERG: SHOW TABLES reports is_iceberg = 'Y'
SHOW TABLES LIKE 'HISTORICO_TRANSACCIONES_ICEBERG' IN SCHEMA SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA;

-- 5b. Row parity with the source mart (18 000)
SELECT
    (SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS) AS FUENTE,
    (SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.HISTORICO_TRANSACCIONES_ICEBERG) AS ICEBERG;

-- 5c. Sample of the historical slice
SELECT *
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.HISTORICO_TRANSACCIONES_ICEBERG
ORDER BY MONTO DESC
LIMIT 5;

-- 5d. Physical open-format artifacts on the internal stage: the historical
--     slice exported as Parquet (readable by Spark, Athena, DuckDB, Flink...).
LIST @STAGING_SCHEMA.ICEBERG_DEMO_STAGE/historico_transacciones/;
