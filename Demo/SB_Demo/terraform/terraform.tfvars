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
schema_core         = "CORE_BANKING_SCHEMA"
schema_analytics    = "RISK_ANALYTICS_SCHEMA"
schema_staging      = "STAGING_SCHEMA"
schema_governance   = "GOVERNANCE_SCHEMA"
schema_vector_store = "CORTEX_VECTOR_STORE"

# Warehouses
wh_ingestion = "WH_INGESTION_MEDIUM"
wh_cortex    = "WH_TRANSFORM_LARGE"
wh_app       = "WH_APP_MEDIUM"

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

# External integrations (integrations.tf). Passwords come ONLY from
# TF_VAR_idmc_cdi_password / TF_VAR_idmc_cdgc_password / TF_VAR_bi_analyst_password.
schema_idmc_landing      = "IDMC_LANDING_SCHEMA"
role_idmc_integration    = "FR_IDMC_INTEGRATION"
role_catalog_reader      = "FR_CATALOG_READER"
create_integration_users = true
user_idmc_cdi            = "SVC_IDMC_CDI"
user_idmc_cdgc           = "SVC_IDMC_CDGC"
user_bi_analyst          = "DEMO_ANALYST"
