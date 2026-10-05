# ============================================================================
# Snowflake Platform Demo — Approved Banking Targets
# ============================================================================
# Values follow the APPROVED mapping in ../naming-conventions.md.
# This file contains no secrets — only object names.
# ============================================================================

# Databases
demo_db_name       = "SUPERINTENDENCY_DEMO_DB"
native_app_db_name = "CORTEX_NATIVE_APP_DB"

# Schemas
schema_core       = "CORE_BANKING_SCHEMA"
schema_analytics  = "RISK_ANALYTICS_SCHEMA"
schema_staging    = "STAGING_SCHEMA"
schema_governance = "GOVERNANCE_SCHEMA"

# Warehouses
wh_ingestion = "WH_INGESTION_XSMALL"
wh_cortex    = "WH_CORTEX_LARGE"
wh_app       = "WH_APP_XSMALL"

# Roles
role_admin    = "FR_DEMO_ADMIN"
role_engineer = "FR_DATA_ENGINEER"
role_analyst  = "FR_BI_ANALYST"

# Operator user holding the role hierarchy root (inherits engineer + analyst)
operator_user = "OPERATIONS"

# Governance objects
masking_policy_national_id = "MASK_NATIONAL_ID"
masking_policy_credit_card = "MASK_CREDIT_CARD"
row_access_policy_name     = "RLS_BUSINESS_UNIT"
rls_mapping_table          = "ROLE_MAPPING"

# Policy attachment happens AFTER the session data scripts create the tables.
attach_policies_to_tables = true
