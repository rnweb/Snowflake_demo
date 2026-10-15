-- =============================================================================
-- Session 2 — 04: Streamlit deployment (PUT + CREATE STREAMLIT)
-- =============================================================================
-- HUMAN APPROVAL REQUIRED — the automation never deploys apps; this script is
-- the documented, repeatable step a presenter runs after explicit review of
-- streamlit_app.py (guardrail: prompts/03-execution-validation.md).
--
-- Run from the repository root with snowsql (PUT is a client command — it
-- works in snowsql scripts but NOT in a Snowsight worksheet):
--
--   snowsql -c <connection> -f Demo/SB_Demo/scripts/session-2-analytics-ai/sql/04_deploy_streamlit.sql
--
-- Run as FR_DATA_ENGINEER (holds CREATE STREAMLIT + stage READ/WRITE on
-- CORTEX_NATIVE_APP_DB.PUBLIC — see terraform/security.tf).
-- Expected: SHOW STREAMLITS returns PANEL_PREVENCION_FRAUDE with
-- query_warehouse WH_APP_XSMALL (small warehouse — trial-credit guardrail).
-- =============================================================================

USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_APP_XSMALL;
USE DATABASE CORTEX_NATIVE_APP_DB;
USE SCHEMA PUBLIC;

PUT file://Demo/SB_Demo/scripts/session-2-analytics-ai/streamlit_app.py
  @CORTEX_NATIVE_APP_DB.PUBLIC.STREAMLIT_STAGE OVERWRITE=TRUE;

CREATE OR REPLACE STREAMLIT PANEL_PREVENCION_FRAUDE
  ROOT_LOCATION = '@CORTEX_NATIVE_APP_DB.PUBLIC.STREAMLIT_STAGE'
  MAIN_FILE      = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'WH_APP_XSMALL'
  COMMENT = 'Panel de Prevención de Fraude — demo Superintendencia de Bancos';

SHOW STREAMLITS IN DATABASE CORTEX_NATIVE_APP_DB;
