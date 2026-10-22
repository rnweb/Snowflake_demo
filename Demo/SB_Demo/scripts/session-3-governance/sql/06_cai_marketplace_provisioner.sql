-- =============================================================================
-- Session 3 — 06: Service identity for IDMC CAI (Data Marketplace automation)
--                 (xlsx C08-AE-07 and C08-AE-08, automatic delivery)
-- =============================================================================
-- CAI processes p_SB_MP_Atender / p_SB_MP_Revogar run blocks A and C of
-- script 05 with this identity. Least privilege:
--   * FR_MP_PROVISIONER can CREATE USER and owns FR_EXTERNAL_READER, so it can
--     grant/revoke ONLY that role. Users it creates are owned by it, so it can
--     disable/drop only those users. It reads no data.
--   * SVC_CAI_MARKETPLACE is a SERVICE user (no interactive login) that
--     authenticates only with a role-restricted PAT.
-- Prerequisite: block 0 of script 05 (role FR_EXTERNAL_READER exists).
-- Idempotent: safe to re-run on the current and on the new account.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS FR_MP_PROVISIONER
  COMMENT = 'IDMC CAI: provisions/revokes external Marketplace consumers (C08-AE-07/08).';
GRANT ROLE FR_MP_PROVISIONER TO ROLE SYSADMIN;

GRANT CREATE USER ON ACCOUNT TO ROLE FR_MP_PROVISIONER;
GRANT USAGE ON WAREHOUSE WH_APP_XSMALL TO ROLE FR_MP_PROVISIONER;

-- Owning FR_EXTERNAL_READER lets the provisioner grant/revoke it (and nothing else).
-- COPY CURRENT GRANTS keeps the SELECT/USAGE grants made in script 05 block 0.
GRANT OWNERSHIP ON ROLE FR_EXTERNAL_READER TO ROLE FR_MP_PROVISIONER COPY CURRENT GRANTS;
-- Keep the admin able to use the external role for validation
GRANT ROLE FR_EXTERNAL_READER TO ROLE FR_DEMO_ADMIN;

-- -----------------------------------------------------------------------------
-- Service user + Programmatic Access Token (PAT) for the Snowflake SQL API.
-- CAI calls POST https://<account>.snowflakecomputing.com/api/v2/statements with
--   Authorization: Bearer <PAT>
--   X-Snowflake-Authorization-Token-Type: PROGRAMMATIC_ACCESS_TOKEN
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS SVC_CAI_MARKETPLACE
  TYPE = SERVICE
  DEFAULT_ROLE = FR_MP_PROVISIONER
  DEFAULT_WAREHOUSE = WH_APP_XSMALL
  DEFAULT_SECONDARY_ROLES = ()
  COMMENT = 'IDMC CAI Data Marketplace automation (demo SB).';
GRANT ROLE FR_MP_PROVISIONER TO USER SVC_CAI_MARKETPLACE;

-- PATs of SERVICE users require a network policy by default. IDMC CAI calls come
-- from Informatica cloud IPs (not fixed for the demo), so the policy below waives
-- that requirement for THIS user only. In production: network policy with the
-- IDMC POD egress IPs instead.
CREATE AUTHENTICATION POLICY IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.AUTH_CAI_PAT
  AUTHENTICATION_METHODS = ('PROGRAMMATIC_ACCESS_TOKEN')
  PAT_POLICY = (NETWORK_POLICY_EVALUATION = ENFORCED_NOT_REQUIRED)
  COMMENT = 'SVC_CAI_MARKETPLACE: PAT only.';
ALTER USER SVC_CAI_MARKETPLACE
  SET AUTHENTICATION POLICY SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.AUTH_CAI_PAT;

-- The token secret is shown ONCE in the result grid (column token_secret).
-- Copy it straight into the CAI connection; never into chat, docs or the repo.
ALTER USER SVC_CAI_MARKETPLACE ADD PROGRAMMATIC ACCESS TOKEN CAI_MARKETPLACE_PAT
  ROLE_RESTRICTION = 'FR_MP_PROVISIONER'
  DAYS_TO_EXPIRY = 30
  COMMENT = 'IDMC CAI p_SB_MP_Atender / p_SB_MP_Revogar';
-- Rotate:  ALTER USER SVC_CAI_MARKETPLACE ROTATE PROGRAMMATIC ACCESS TOKEN CAI_MARKETPLACE_PAT;
-- Revoke:  ALTER USER SVC_CAI_MARKETPLACE REMOVE PROGRAMMATIC ACCESS TOKEN CAI_MARKETPLACE_PAT;

-- -----------------------------------------------------------------------------
-- Validation (run as the provisioner role)
-- -----------------------------------------------------------------------------
-- USE ROLE FR_MP_PROVISIONER;
-- SHOW GRANTS TO ROLE FR_MP_PROVISIONER;      -- expected: CREATE USER, USAGE WH, OWNERSHIP FR_EXTERNAL_READER
-- SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS;
--   expected: error (the provisioner reads no data)
