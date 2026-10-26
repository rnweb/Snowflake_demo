-- =============================================================================
-- Session 3 — 05: Governed external access via IDMC Data Marketplace
--                 (xlsx C08-AE-07 and C08-AE-08)
-- =============================================================================
-- Story
--   1. An external analyst (no Snowflake access) finds "Transacciones de
--      Tarjeta (enmascarado)" in the IDMC Data Marketplace and requests it.
--   2. The data owner approves the order in the Marketplace.
--   3. Fulfilment = section A below (temporary user + masked, row-filtered role).
--   4. The analyst connects from Python / Power BI and sees ONLY masked PYME rows.
--   5. The owner withdraws the order; section C revokes access; reconnect fails.
--
-- Run sections A and C as FR_DEMO_ADMIN (CREATE USER comes from ACCOUNTADMIN
-- or a role with CREATE USER).
--
-- CREDENTIALS: this file never contains a password or key, not even a
-- placeholder. The user is created WITHOUT a password. An admin must configure
-- the login OUT OF BAND, in a Snowsight worksheet or with a key pair, and hand
-- it to the external analyst through a secure channel (never in chat, email,
-- this repository or a script). Example, after section A runs:
--   ALTER USER EXT_ANALISTA_PYME SET PASSWORD = '<generated in the worksheet>';
--   -- or key pair: ALTER USER EXT_ANALISTA_PYME SET RSA_PUBLIC_KEY = '<public key body>';
-- MUST_CHANGE_PASSWORD = TRUE forces the analyst to choose a new password at
-- first login. DAYS_TO_EXPIRY limits the account lifetime regardless.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. One-time: role for external consumers + RLS mapping (PYME only)
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
CREATE ROLE IF NOT EXISTS FR_EXTERNAL_READER
  COMMENT = 'External consumers approved via IDMC Data Marketplace: masked PII, PYME rows only.';
GRANT ROLE FR_EXTERNAL_READER TO ROLE FR_DEMO_ADMIN;

GRANT USAGE ON WAREHOUSE WH_APP_MEDIUM TO ROLE FR_EXTERNAL_READER;
GRANT USAGE ON DATABASE SUPERINTENDENCY_DEMO_DB TO ROLE FR_EXTERNAL_READER;
GRANT USAGE ON SCHEMA SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA TO ROLE FR_EXTERNAL_READER;
-- Only the ordered asset — nothing else in the schema
GRANT SELECT ON TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
  TO ROLE FR_EXTERNAL_READER;

-- Without a ROLE_MAPPING row the RLS policy returns ZERO rows (no error)
INSERT INTO SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING (ROLE_NAME, BUSINESS_UNIT, DESCRIPTION)
SELECT 'FR_EXTERNAL_READER', 'PYME', 'External consumer via Data Marketplace'
WHERE NOT EXISTS (SELECT 1 FROM SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING
                  WHERE ROLE_NAME = 'FR_EXTERNAL_READER');

-- -----------------------------------------------------------------------------
-- A. FULFILMENT (after the Marketplace order is approved)
--    Time-boxed user: expires by itself in 1 day even if nobody revokes it.
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
-- No PASSWORD clause on purpose: see CREDENTIALS above (set out of band).
CREATE USER IF NOT EXISTS EXT_ANALISTA_PYME
  MUST_CHANGE_PASSWORD = TRUE
  DEFAULT_ROLE = FR_EXTERNAL_READER
  DEFAULT_WAREHOUSE = WH_APP_MEDIUM
  DEFAULT_SECONDARY_ROLES = ()
  DAYS_TO_EXPIRY = 1
  COMMENT = 'External analyst — IDMC Data Marketplace order <nº do pedido>';
GRANT ROLE FR_EXTERNAL_READER TO USER EXT_ANALISTA_PYME;
-- Re-running the demo: the user already exists (disabled by block C), so re-enable it
ALTER USER EXT_ANALISTA_PYME SET DISABLED = FALSE DAYS_TO_EXPIRY = 1;

-- -----------------------------------------------------------------------------
-- B. VALIDATION (what the external analyst sees) — run as the user, or from
--    scripts/session-3-governance/python/check_external_access.py
-- -----------------------------------------------------------------------------
-- USE ROLE FR_EXTERNAL_READER;
-- SELECT UNIDAD_NEGOCIO, COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS GROUP BY 1;
--   expected: PYME | 17523213
-- SELECT RUT, NUMERO_TARJETA, MONTO FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS LIMIT 5;
--   expected: ***-**-<hash> | ****-****-****-****
-- SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM;
--   expected: error 002003 (not part of the order)

-- Audit trail of the external session (C08-AE-04 reuse)
SELECT start_time, user_name, role_name, LEFT(query_text, 100) AS query, execution_status
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(
       USER_NAME => 'EXT_ANALISTA_PYME', RESULT_LIMIT => 50))
ORDER BY start_time DESC;

-- -----------------------------------------------------------------------------
-- C. REVOCATION (after the owner withdraws the order in the Marketplace)
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
ALTER USER EXT_ANALISTA_PYME SET DISABLED = TRUE;      -- kills new logins immediately
REVOKE ROLE FR_EXTERNAL_READER FROM USER EXT_ANALISTA_PYME;
SHOW GRANTS TO USER EXT_ANALISTA_PYME;                  -- expected: no roles
-- After the demo:  DROP USER EXT_ANALISTA_PYME;
