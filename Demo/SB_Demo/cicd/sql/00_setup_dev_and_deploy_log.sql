-- ============================================================================
-- C05 setup — run ONCE as ACCOUNTADMIN (or FR_DEMO_ADMIN) before the 1st pipeline run
-- ============================================================================
-- DEV = zero-copy clone of PROD: no extra storage until data diverges, same
-- policies, same structure. Child-object grants are cloned; database-level
-- grants are not, hence the GRANT USAGE below.
-- ============================================================================
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB_DEV
  CLONE SUPERINTENDENCY_DEMO_DB
  COMMENT = 'C05 DEV environment: zero-copy clone of SUPERINTENDENCY_DEMO_DB';

GRANT USAGE ON DATABASE SUPERINTENDENCY_DEMO_DB_DEV TO ROLE FR_DATA_ENGINEER;
GRANT USAGE ON DATABASE SUPERINTENDENCY_DEMO_DB_DEV TO ROLE FR_DEMO_ADMIN;

-- The pipeline user (TRIADE) must be able to use FR_DATA_ENGINEER.
-- GRANT ROLE FR_DATA_ENGINEER TO USER TRIADE;   -- only if not already granted

-- Deployment log (PROD and DEV) — AE-04 traceability
CREATE TABLE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.DEPLOYMENT_LOG (
    BUILD_ID     VARCHAR,
    GIT_COMMIT   VARCHAR,
    AUTHOR       VARCHAR,
    SOURCE_REF   VARCHAR,
    TARGET_ENV   VARCHAR,
    DEPLOYED_AT  TIMESTAMP_LTZ
) COMMENT = 'One row per Azure DevOps deployment (C05-AE-04).';
GRANT INSERT, SELECT ON TABLE SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.DEPLOYMENT_LOG
  TO ROLE FR_DATA_ENGINEER;

-- Checks
SHOW DATABASES LIKE 'SUPERINTENDENCY_DEMO_DB%';
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB_DEV.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS;  -- 50000000 as admin (PG-06)
