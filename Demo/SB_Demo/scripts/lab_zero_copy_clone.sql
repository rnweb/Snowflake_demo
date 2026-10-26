-- =============================================================================
-- LAB: Zero-copy clone storage efficiency (CLIENT_PROFILE_DIM)
-- =============================================================================
-- Goal: show that a clone shares the base table's micro-partitions and that
-- only the rows written to the clone add storage.
--
-- Role: FR_DATA_ENGINEER (owns CLIENT_PROFILE_DIM; dbt runs as this role).
-- Warehouse: WH_INGESTION_MEDIUM (cheap for a lab; not WH_TRANSFORM_LARGE).
--
-- PRESENTER NOTES (verified against the live account, 2026-10):
--   1. CLIENT_PROFILE_DIM is TRANSIENT (dbt config, dbt/dbt_project.yml). A
--      transient table can only be cloned into a TRANSIENT table, otherwise
--      Snowflake fails with 002120. The clone is therefore created as
--      TRANSIENT TABLE, not the plain CREATE TABLE ... CLONE in the brief.
--   2. INFORMATION_SCHEMA.TABLE_STORAGE_METRICS returns NO rows in this
--      account (checked as FR_DATA_ENGINEER and FR_DEMO_ADMIN). The lab uses
--      SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS, which has up to ~3 h
--      latency and keeps history rows, so run section E ahead of time.
--   3. The base table is small (600 rows, ~25 KB). Byte differences are
--      therefore tiny. The explanation is the point, not the size. For a
--      visible difference, repeat the lab on CREDIT_CARD_TRANSACTIONS (50M rows,
--      ~810 MB), which is also cloneable only as TRANSIENT.
--   4. TABLES.BYTES (section B/D) is the LOGICAL size of each table. A clone
--      reports the same logical size as its base even though it stores nothing
--      extra. Storage efficiency is shown by ACTIVE_BYTES in section E.
--
-- Cleanup (section F) drops the clone only. The base table is never modified.
-- =============================================================================

USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_INGESTION_MEDIUM;
USE DATABASE SUPERINTENDENCY_DEMO_DB;
USE SCHEMA CORE_BANKING_SCHEMA;


-- =============================================================================
-- A. BASELINE TABLE
-- =============================================================================
SELECT 'CLIENT_PROFILE_DIM' AS BASE_TABLE, COUNT(*) AS ROW_COUNT
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM;


-- =============================================================================
-- B. CURRENT SIZE (before the clone)
-- =============================================================================
SELECT TABLE_NAME, ROW_COUNT, BYTES AS LOGICAL_BYTES, IS_TRANSIENT
FROM SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CORE_BANKING_SCHEMA'
  AND TABLE_NAME = 'CLIENT_PROFILE_DIM';


-- =============================================================================
-- C. ZERO-COPY CLONE (metadata operation: no data is copied)
-- =============================================================================
-- Transient to match the base (see note 1). Re-runnable.
CREATE OR REPLACE TRANSIENT TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM_CLONE
    CLONE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM;

-- Right after cloning: same row count as the base.
SELECT 'CLONE_AFTER_CREATE' AS STEP, COUNT(*) AS ROW_COUNT
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM_CLONE;


-- =============================================================================
-- D. WRITE NEW ROWS ONLY INTO THE CLONE
-- =============================================================================
-- Synthetic RUTs ('LAB-') are used so the rows are easy to identify and remove.
-- Columns are listed explicitly, so the insert works whether or not the
-- optional RISK_PROFILE column (CDC lab, 05_demo_cdc_crm_updates.sql) exists.
INSERT INTO SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM_CLONE
    (RUT, NOMBRE, APELLIDO, CIUDAD, REGION, ESTADO_CLIENTE, FECHA_ALTA, FECHA_ACTUALIZACION)
SELECT
    'LAB-' || LPAD(SEQ4()::VARCHAR, 4, '0'),
    'LAB', 'ZERO_COPY', 'SANTIAGO', 'RM', 'ACTIVO',
    CURRENT_DATE(), CURRENT_TIMESTAMP()
FROM TABLE(GENERATOR(ROWCOUNT => 5));

-- Proof of isolation: the clone grew by 5, the base did NOT change.
SELECT 'BASE'  AS TABLE_ROLE, COUNT(*) AS ROW_COUNT
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
UNION ALL
SELECT 'CLONE' AS TABLE_ROLE, COUNT(*) AS ROW_COUNT
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM_CLONE;
-- expected: BASE = 600 (unchanged), CLONE = 605

-- The new rows exist only in the clone.
SELECT COUNT(*) AS LAB_ROWS_IN_BASE
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
WHERE RUT LIKE 'LAB-%';
-- expected: 0


-- =============================================================================
-- E. STORAGE EVIDENCE: shared micro-partitions vs. new bytes
-- =============================================================================
-- Read ACTIVE_BYTES as "bytes this table owns":
--   * a clone that has not been written to owns ~0 ACTIVE_BYTES, because it
--     references the base table's micro-partitions;
--   * after the insert, the clone owns only the new partition(s) for the 5 rows.
-- The view lags and keeps history rows. Filter by TABLE_NAME and read the most
-- recent entries. Check this in a rehearsal before the audience arrives.
SELECT TABLE_NAME, ACTIVE_BYTES, TIME_TRAVEL_BYTES, FAILSAFE_BYTES, CLONE_GROUP_ID
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE TABLE_NAME IN ('CLIENT_PROFILE_DIM', 'CLIENT_PROFILE_DIM_CLONE')
ORDER BY TABLE_NAME, CLONE_GROUP_ID;

-- Logical size (live): the clone matches the base because a clone presents the
-- same data. This does NOT measure storage sharing (see note 4).
SELECT TABLE_NAME, ROW_COUNT, BYTES AS LOGICAL_BYTES, IS_TRANSIENT
FROM SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CORE_BANKING_SCHEMA'
  AND TABLE_NAME IN ('CLIENT_PROFILE_DIM', 'CLIENT_PROFILE_DIM_CLONE')
ORDER BY TABLE_NAME;


-- =============================================================================
-- F. CLEAN-UP (drops the clone only; the base table is untouched)
-- =============================================================================
DROP TABLE IF EXISTS SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM_CLONE;

-- Confirm: the base table is still 600 rows and the clone no longer exists.
SELECT COUNT(*) AS BASE_ROWS_AFTER_CLEANUP
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM;
-- expected: 600
