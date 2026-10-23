-- =============================================================================
-- Session 3 — 04: Audit logs (xlsx C08-PRE-05, C08-AE-04, C08-AE-05)
-- =============================================================================
-- Run as FR_DEMO_ADMIN (or ACCOUNTADMIN). ACCOUNT_USAGE views need IMPORTED
-- PRIVILEGES on the SNOWFLAKE database or the GOVERNANCE_VIEWER database role.
--
-- Latency reminder (plan the demo around it):
--   INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER  -> real time, 7 days
--   ACCOUNT_USAGE.QUERY_HISTORY / LOGIN_HISTORY -> up to ~45 min / 2 h
--   ACCOUNT_USAGE.ACCESS_HISTORY               -> up to ~3 h
-- => generate the DEMO_ANALYST activity the DAY BEFORE for ACCESS_HISTORY,
--    and use QUERY_HISTORY_BY_USER for the "live" part.
-- =============================================================================

USE ROLE FR_DEMO_ADMIN;
USE WAREHOUSE WH_APP_MEDIUM;

-- -----------------------------------------------------------------------------
-- 0. Generate activity as DEMO_ANALYST (run in a separate session/worksheet)
-- -----------------------------------------------------------------------------
-- USE ROLE FR_BI_ANALYST;
-- SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS;  -- allowed (15969793)
-- SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.<raw_table>;                   -- DENIED

-- -----------------------------------------------------------------------------
-- 1. AE-04 (live): what did DEMO_ANALYST do in the last hour? allowed vs denied
-- -----------------------------------------------------------------------------
SELECT start_time,
       user_name,
       role_name,
       query_type,
       LEFT(query_text, 120)                                   AS query,
       execution_status,                                       -- SUCCESS / FAILED_WITH_ERROR
       IFF(execution_status = 'SUCCESS', 'PERMITIDO', 'DENEGADO') AS resultado,
       error_message
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(
         USER_NAME => 'DEMO_ANALYST',
         END_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP()),
         RESULT_LIMIT => 100))
ORDER BY start_time DESC;

-- -----------------------------------------------------------------------------
-- 2. AE-04 (column level): which objects/columns were read, by whom, when
--    (ACCOUNT_USAGE.ACCESS_HISTORY — Enterprise feature, ~3 h latency)
-- -----------------------------------------------------------------------------
SELECT ah.query_start_time,
       ah.user_name,
       obj.value:"objectName"::STRING        AS objeto,
       col.value:"columnName"::STRING        AS columna
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
     LATERAL FLATTEN(ah.base_objects_accessed)      obj,
     LATERAL FLATTEN(obj.value:"columns", OUTER => TRUE) col
WHERE ah.user_name = 'DEMO_ANALYST'
  AND ah.query_start_time >= DATEADD('day', -2, CURRENT_TIMESTAMP())
ORDER BY ah.query_start_time DESC
LIMIT 100;

-- Logins (successful and failed) for the same user
SELECT event_timestamp, user_name, client_ip, reported_client_type,
       first_authentication_factor, is_success, error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE user_name = 'DEMO_ANALYST'
ORDER BY event_timestamp DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- 3. AE-05: logs are immutable — even ACCOUNTADMIN cannot alter them
--    Each statement below is EXPECTED TO FAIL. Show the error on screen.
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
DELETE FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY WHERE user_name = 'DEMO_ANALYST';
UPDATE SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY SET user_name = 'X';
DROP VIEW SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY;
-- Talking point: SNOWFLAKE is a system-owned shared database (read-only for
-- every role); history is retained 365 days by Snowflake, outside customer control.
USE ROLE FR_DEMO_ADMIN;

-- -----------------------------------------------------------------------------
-- 4. PRE-05: declared, configurable retention
--    Native: ACCOUNT_USAGE = 365 days (fixed), INFORMATION_SCHEMA = 7-14 days.
--    Configurable: copy to an institutional audit table whose retention the
--    bank controls (e.g. 7 years), protected from changes by Time Travel and
--    granted SELECT-only to auditors.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.AUDIT_QUERY_LOG
  DATA_RETENTION_TIME_IN_DAYS = 90       -- Time Travel window (Enterprise max 90)
  COMMENT = 'Audit log copy. Retention policy: 7 years. Source: ACCOUNT_USAGE.QUERY_HISTORY.'
AS
SELECT query_id, start_time, user_name, role_name, query_type,
       execution_status, error_message, query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP());

SHOW TABLES LIKE 'AUDIT_QUERY_LOG' IN SCHEMA SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA;
