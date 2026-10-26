-- =============================================================================
-- Session 5 — 05: Native CDC demo — CRM updates via STREAM + TASK (live)
-- =============================================================================
-- Scenario: the IDMC side does not show live CDC, so the landing is mocked:
-- CRM change events land in IDMC_LANDING_SCHEMA.CRM_CLIENT_UPDATES_RAW. A
-- stream captures them and a task merges the micro-batch into the curated
-- CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM — only when the stream has data.
--
-- Objects (SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA unless noted):
--   CRM_CLIENT_UPDATES_RAW   landing table (mock CRM events)
--   STR_CRM_CLIENT_UPDATES   standard stream on the landing table
--   TSK_MERGE_CRM_UPDATES    task, WH_TRANSFORM_LARGE, WHEN stream has data
--   CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM  merge target (dbt-managed table)
--
-- Role: FR_DATA_ENGINEER (owns the landing objects, the task, and the target).
--
-- ---------------------------------------------------------------------------
-- PROJECT-STANDARD ADJUSTMENTS (vs. the original spec)
-- ---------------------------------------------------------------------------
--   * CLIENT_PROFILE_DIM has NO RISK_PROFILE / CREDIT_LIMIT columns. Mapping:
--       NUEVO_RIESGO         -> RISK_PROFILE (ADDED by section 2c; NOT part of
--                               the dbt model — see the reset warning below)
--       NUEVO_LIMITE_CREDITO -> LIMITE_CREDITO_TOTAL (existing credit-limit column)
--   * MASK_NATIONAL_ID hides RUT from FR_DATA_ENGINEER (pseudonym
--     '***-**-' || RIGHT(SHA2(RUT,256),12)). A naive ON t.RUT = s.RUT would
--     match ZERO rows for this role and the task would silently do nothing.
--     The MERGE therefore joins on the SAME deterministic token computed from
--     the landing RUT. No unmasking is required. Preflight B proves it.
--
-- ---------------------------------------------------------------------------
-- PRESENTER RULES
-- ---------------------------------------------------------------------------
--   1. Run section 0 (ACCOUNTADMIN grants) ONCE, before the day — not live.
--   2. Run sections 1-2 (setup) and PREFLIGHT before the audience arrives.
--   3. Run section 3 (live demo) in ONE worksheet, top to bottom, same session
--      (the $demo_rut variable lives only in that session).
--   4. The task stays SUSPENDED. If it were RESUMED with its schedule, it
--      would consume the stream within a minute and the presenter would no
--      longer see METADATA$ACTION = INSERT in step 3c.
--   5. After the demo, run section 4 (reset). A plain `dbt build` also resets
--      CLIENT_PROFILE_DIM: it recreates the table, drops RISK_PROFILE and
--      detaches the RUT masking policy (see DEPLOY_ORDER.md). Re-run section 2
--      after any dbt build before presenting again.
-- =============================================================================


-- =============================================================================
-- SECTION 0 — ONE-TIME BOOTSTRAP GRANTS (ACCOUNTADMIN, once, not live)
-- =============================================================================
-- EXECUTE TASK is an account-level privilege; it was granted outside Terraform
-- (batch A1, 2026-10-22). The schema-level grants below are not in
-- terraform/security.tf or integrations.tf yet — codify them there as a
-- follow-up to avoid drift. Uncomment and run as ACCOUNTADMIN:
--
-- USE ROLE ACCOUNTADMIN;
-- GRANT EXECUTE TASK ON ACCOUNT TO ROLE FR_DATA_ENGINEER;
-- GRANT USAGE ON WAREHOUSE WH_TRANSFORM_LARGE TO ROLE FR_DATA_ENGINEER;
-- GRANT USAGE       ON SCHEMA SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA TO ROLE FR_DATA_ENGINEER;
-- GRANT CREATE TABLE  ON SCHEMA SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA TO ROLE FR_DATA_ENGINEER;
-- GRANT CREATE STREAM ON SCHEMA SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA TO ROLE FR_DATA_ENGINEER;
-- GRANT CREATE TASK   ON SCHEMA SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA TO ROLE FR_DATA_ENGINEER;
-- -- The merge target needs no grant: FR_DATA_ENGINEER owns CLIENT_PROFILE_DIM
-- -- (dbt runs as FR_DATA_ENGINEER) and holds MODIFY on CORE_BANKING_SCHEMA
-- -- (terraform/security.tf, engineer_core_build).
-- USE ROLE FR_DATA_ENGINEER;


-- =============================================================================
-- SECTION 1 — CONTEXT (FR_DATA_ENGINEER)
-- =============================================================================
USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_TRANSFORM_LARGE;
USE DATABASE SUPERINTENDENCY_DEMO_DB;
USE SCHEMA IDMC_LANDING_SCHEMA;


-- =============================================================================
-- SECTION 2 — SETUP: landing table, stream, target column, merge task
-- =============================================================================

-- 2a. Landing table (mock CRM events; IDMC CDI would land the same shape)
CREATE TABLE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.CRM_CLIENT_UPDATES_RAW (
    RUT                  VARCHAR,
    NUEVO_RIESGO         VARCHAR,
    NUEVO_LIMITE_CREDITO NUMBER,
    UPDATE_TIMESTAMP     TIMESTAMP
)
COMMENT = 'Mock CRM change events for the native CDC demo (stream + task)';

-- 2b. Stream: captures every INSERT into the landing table since the last consume
CREATE STREAM IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.STR_CRM_CLIENT_UPDATES
    ON TABLE SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.CRM_CLIENT_UPDATES_RAW
    COMMENT = 'CDC stream on CRM_CLIENT_UPDATES_RAW';

-- 2c. Target column the demo updates (not in the dbt model; see header).
--     ADD COLUMN IF NOT EXISTS is idempotent. FR_DATA_ENGINEER owns the table.
ALTER TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
    ADD COLUMN IF NOT EXISTS RISK_PROFILE VARCHAR;

-- 2d. Merge task. Created SUSPENDED (CREATE OR REPLACE never auto-resumes).
--     Micro-batch: only INSERT actions, one row per RUT (latest timestamp wins),
--     so a duplicate RUT in one batch cannot fail the MERGE.
--     The ON clause uses the masking token (see header).
CREATE OR REPLACE TASK SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.TSK_MERGE_CRM_UPDATES
    WAREHOUSE = WH_TRANSFORM_LARGE
    SCHEDULE  = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.STR_CRM_CLIENT_UPDATES')
    COMMENT   = 'Micro-batch MERGE: CRM updates stream -> CLIENT_PROFILE_DIM (risk + credit limit)'
AS
MERGE INTO SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM AS t
USING (
    SELECT RUT, NUEVO_RIESGO, NUEVO_LIMITE_CREDITO
    FROM SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.STR_CRM_CLIENT_UPDATES
    WHERE METADATA$ACTION = 'INSERT'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY RUT ORDER BY UPDATE_TIMESTAMP DESC) = 1
) AS s
    ON t.RUT = '***-**-' || RIGHT(SHA2(s.RUT, 256), 12)
WHEN MATCHED THEN UPDATE SET
    t.RISK_PROFILE         = s.NUEVO_RIESGO,
    t.LIMITE_CREDITO_TOTAL = s.NUEVO_LIMITE_CREDITO,
    t.FECHA_ACTUALIZACION  = CURRENT_TIMESTAMP();

-- 2e. Confirm the task exists and is SUSPENDED (expected: state = suspended)
SHOW TASKS LIKE 'TSK_MERGE_CRM_UPDATES' IN SCHEMA SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA;


-- =============================================================================
-- PREFLIGHT (run before the audience arrives)
-- =============================================================================

-- A. Pick a real client as the demo subject (plaintext RUT, staging layer).
--    The session variable is used by section 3 — keep this worksheet open.
SET demo_rut = (
    SELECT RUT
    FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.CLIENTES
    ORDER BY RUT
    LIMIT 1
);
SELECT $demo_rut AS DEMO_RUT_PLAINTEXT;

-- B. Join proof under FR_DATA_ENGINEER: the pseudonym join must match ALL 600
--    dim rows. If fewer match, the MERGE would silently do nothing — do not
--    run the demo.
SELECT COUNT(*) AS MATCHED_ROWS
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM t
JOIN SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.CLIENTES s
  ON t.RUT = '***-**-' || RIGHT(SHA2(s.RUT, 256), 12);
-- expected: 600

-- C. Stream starts empty (no pending events from earlier rehearsals).
SELECT SYSTEM$STREAM_HAS_DATA('SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.STR_CRM_CLIENT_UPDATES') AS STREAM_HAS_DATA;
-- expected: false (if true, run section 4 first)


-- =============================================================================
-- SECTION 3 — LIVE DEMO (run top to bottom in ONE worksheet)
-- =============================================================================

-- 3a. BEFORE — the client's current risk profile and credit limit.
--     Shown as the pseudonym because the presenter runs as FR_DATA_ENGINEER.
--     To show the plaintext RUT, run this one query as FR_DEMO_ADMIN.
SELECT RUT, RISK_PROFILE, LIMITE_CREDITO_TOTAL, FECHA_ACTUALIZACION
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
WHERE RUT = '***-**-' || RIGHT(SHA2($demo_rut, 256), 12);

-- 3b. The CRM event arrives: risk changes to ALTO, credit limit to 2 500 000.
INSERT INTO SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.CRM_CLIENT_UPDATES_RAW
    (RUT, NUEVO_RIESGO, NUEVO_LIMITE_CREDITO, UPDATE_TIMESTAMP)
VALUES
    ($demo_rut, 'ALTO', 2500000, CURRENT_TIMESTAMP());

-- 3c. The stream now holds the change. METADATA$ACTION = 'INSERT' shows the
--     event waiting for the next micro-batch. Querying a stream does NOT
--     consume it; only the MERGE does.
SELECT
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID,
    RUT,
    NUEVO_RIESGO,
    NUEVO_LIMITE_CREDITO,
    UPDATE_TIMESTAMP
FROM SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.STR_CRM_CLIENT_UPDATES;

-- 3d. Run the micro-batch now (the schedule is intentionally not used live).
EXECUTE TASK TSK_MERGE_CRM_UPDATES;

-- 3e. Task result (a few seconds after 3d). STATE = SUCCEEDED is the target.
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, ERROR_MESSAGE
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.TASK_HISTORY(
    TASK_NAME => 'TSK_MERGE_CRM_UPDATES',
    SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP())
))
ORDER BY SCHEDULED_TIME DESC
LIMIT 1;

-- 3f. The stream is consumed: no pending events (expected: false).
SELECT SYSTEM$STREAM_HAS_DATA('SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.STR_CRM_CLIENT_UPDATES') AS STREAM_HAS_DATA;

-- 3g. AFTER — same query as 3a. RISK_PROFILE = 'ALTO' and the new limit.
SELECT RUT, RISK_PROFILE, LIMITE_CREDITO_TOTAL, FECHA_ACTUALIZACION
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
WHERE RUT = '***-**-' || RIGHT(SHA2($demo_rut, 256), 12);


-- =============================================================================
-- SECTION 4 — RESET (after the demo, or before a rehearsal)
-- =============================================================================

-- 4a. Clear the landing table. Rows already merged are gone from the stream,
--     so this leaves the stream empty for the next run.
DELETE FROM SUPERINTENDENCY_DEMO_DB.IDMC_LANDING_SCHEMA.CRM_CLIENT_UPDATES_RAW;

-- 4b. Put the demo client back to its pre-demo state (RISK_PROFILE was NULL).
UPDATE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
SET RISK_PROFILE = NULL
WHERE RUT = '***-**-' || RIGHT(SHA2($demo_rut, 256), 12);

-- 4c. LIMITE_CREDITO_TOTAL is dbt-derived. It is restored by `dbt build`
--     (DEPLOY_ORDER.md), and that build also drops RISK_PROFILE, so re-run
--     section 2 afterwards. Re-apply the RUT masking as documented there.
