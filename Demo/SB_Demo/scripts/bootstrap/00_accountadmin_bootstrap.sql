-- =============================================================================
-- Bootstrap — run ONCE per Snowflake account as ACCOUNTADMIN, before
-- `terraform apply`. Account-level grants cannot be issued by FR_TERRAFORM
-- (error 003102), so they live here instead of in Terraform.
-- Idempotent: every statement can be re-run safely.
-- =============================================================================
USE ROLE ACCOUNTADMIN;

-- Session 3 (existing bootstrap, documented in phase3-next-steps.md)
GRANT APPLY MASKING POLICY    ON ACCOUNT TO ROLE FR_DEMO_ADMIN;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE FR_DEMO_ADMIN;

-- External integrations (terraform/integrations.tf): FR_TERRAFORM creates the
-- IDMC and Power BI users.
GRANT CREATE USER ON ACCOUNT TO ROLE FR_TERRAFORM;

-- =============================================================================
-- Run AFTER `terraform apply` (the role must exist):
-- IDMC CDGC reads Snowflake tags and governance views (TAGS, TAG_REFERENCES,
-- ACCESS_HISTORY, ...) through this SNOWFLAKE database role.
-- =============================================================================
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER TO ROLE FR_CATALOG_READER;
