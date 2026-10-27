-- =============================================================================
-- Session 4 — 02: Service identity for IDMC -> Snowflake SQL API (C03-AE-01)
-- =============================================================================
-- IDMC (CAI service connector) calls the native REST endpoint
--   POST https://zkdcmqh-fjc41457.snowflakecomputing.com/api/v2/statements
-- with a Programmatic Access Token restricted to FR_BI_ANALYST, so the API
-- returns governed data: RETAIL rows only (RLS) and masked RUT / card (masking).
-- Same pattern as SVC_CAI_MARKETPLACE (session-3/06), different role.
-- Idempotent. Run as ACCOUNTADMIN. The token is shown ONCE: paste it straight
-- into the IDMC connection, never into chat, docs or the repo.
-- =============================================================================
USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS SVC_IDMC_SQLAPI
  TYPE = SERVICE
  DEFAULT_ROLE = FR_BI_ANALYST
  DEFAULT_WAREHOUSE = WH_APP_MEDIUM
  DEFAULT_SECONDARY_ROLES = ()
  COMMENT = 'C03-AE-01: IDMC consume la SQL API REST de Snowflake (datos gobernados).';
GRANT ROLE FR_BI_ANALYST TO USER SVC_IDMC_SQLAPI;

-- PAT only, network policy not required (IDMC cloud IPs vary) — policy from session-3/06
ALTER USER SVC_IDMC_SQLAPI
  SET AUTHENTICATION POLICY SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.AUTH_CAI_PAT;

ALTER USER SVC_IDMC_SQLAPI ADD PROGRAMMATIC ACCESS TOKEN IDMC_SQLAPI_PAT
  ROLE_RESTRICTION = 'FR_BI_ANALYST'
  DAYS_TO_EXPIRY = 30
  COMMENT = 'IDMC CAI service connector Snowflake_SQL_API';
-- Rotate: ALTER USER SVC_IDMC_SQLAPI ROTATE PROGRAMMATIC ACCESS TOKEN IDMC_SQLAPI_PAT;

-- -----------------------------------------------------------------------------
-- Request the IDMC connector sends (reference for the demo)
-- -----------------------------------------------------------------------------
-- Headers: Authorization: Bearer <PAT>
--          X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN
--          Content-Type: application/json   Accept: application/json
-- Body:    {"statement": "SELECT RUT, NUMERO_TARJETA, CIUDAD, UNIDAD_NEGOCIO, MONTO
--                          FROM CREDIT_CARD_TRANSACTIONS LIMIT 10",
--           "database": "SUPERINTENDENCY_DEMO_DB", "schema": "CORE_BANKING_SCHEMA",
--           "warehouse": "WH_APP_MEDIUM", "role": "FR_BI_ANALYST", "timeout": 60}
-- Expected: HTTP 200, "data" with RETAIL rows only, RUT ***-**-<hash>, card ****-****-****-****.

-- Evidence on the Snowflake side (the API call is audited like any session)
SELECT START_TIME, USER_NAME, ROLE_NAME, LEFT(QUERY_TEXT, 80) AS QUERY, EXECUTION_STATUS
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(
       USER_NAME => 'SVC_IDMC_SQLAPI', RESULT_LIMIT => 20))
ORDER BY START_TIME DESC;
