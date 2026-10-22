-- ============================================================================
-- C05-AE-05 (rollback evidence) and C05-AE-06 (dataset / schema versioning)
-- ============================================================================
USE ROLE FR_DEMO_ADMIN;
USE WAREHOUSE WH_APP_XSMALL;

-- ---------------------------------------------------------------------------
-- A. Code rollback evidence: both versions stay in history
-- ---------------------------------------------------------------------------
SELECT * FROM SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.DEPLOYMENT_LOG
ORDER BY DEPLOYED_AT DESC;

SHOW VIEWS LIKE 'VW_RESUMEN_UNIDAD_NEGOCIO' IN SCHEMA SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA;
-- "comment" column shows the build / commit currently deployed
SELECT GET_DDL('VIEW', 'SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.VW_RESUMEN_UNIDAD_NEGOCIO');

-- ---------------------------------------------------------------------------
-- B. Data versioning (AE-06): Time Travel + zero-copy clone
-- ---------------------------------------------------------------------------
-- B1. Snapshot (tag) the dataset before a change
CREATE OR REPLACE TABLE SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CCT_SNAPSHOT_V1
  CLONE SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS;

-- B2. Simulate a bad change in DEV
SET before_change = CURRENT_TIMESTAMP();
DELETE FROM SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
WHERE UNIDAD_NEGOCIO = 'PYME';

-- B3. Query the past: current vs. before the change
SELECT 'actual' AS version, COUNT(*) FROM SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
UNION ALL
SELECT 'antes',  COUNT(*) FROM SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
  AT (TIMESTAMP => $before_change);

-- B4. Data rollback: restore the table to its pre-change state
CREATE OR REPLACE TABLE SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
  CLONE SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
  AT (TIMESTAMP => $before_change);

-- B5. Schema evolution is versioned too
ALTER TABLE SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CCT_SNAPSHOT_V1 ADD COLUMN CANAL VARCHAR;
SELECT COLUMN_NAME, DATA_TYPE FROM SUPERINTENDENCY_DEMO_DB_DEV.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'CCT_SNAPSHOT_V1' ORDER BY ORDINAL_POSITION;

-- B6. Dropped by mistake? UNDROP
DROP TABLE SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CCT_SNAPSHOT_V1;
UNDROP TABLE SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CCT_SNAPSHOT_V1;
