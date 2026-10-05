# ============================================================================
# Snowflake Platform Demo — Variables
# ============================================================================
# Single source of truth for ALL object names.
# Values live in terraform.tfvars (approved banking targets).
# See ../naming-conventions.md for the approved mapping.
# ============================================================================

# ---------------------------------------------------------------------------
# Databases
# ---------------------------------------------------------------------------
variable "demo_db_name" {
  type        = string
  description = "Primary database housing all session assets."
}

variable "native_app_db_name" {
  type        = string
  description = "Separate database for the Cortex Native App package (required by Native Apps)."
}

# ---------------------------------------------------------------------------
# Schemas (inside demo_db_name)
# ---------------------------------------------------------------------------
variable "schema_core" {
  type        = string
  description = "Raw ingestion layer for transactional data."
}

variable "schema_analytics" {
  type        = string
  description = "Transformed layer for BI, RLS, and Cortex."
}

variable "schema_staging" {
  type        = string
  description = "dbt intermediate layer."
}

variable "schema_governance" {
  type        = string
  description = "Masking/row-access policies and role-mapping tables."
}

# ---------------------------------------------------------------------------
# Warehouses
# ---------------------------------------------------------------------------
variable "wh_ingestion" {
  type        = string
  description = "Compute dedicated to Snowpipe and dbt runs."
}

variable "wh_cortex" {
  type        = string
  description = "Compute allocated for ML and Cortex LLM queries."
}

variable "wh_app" {
  type        = string
  description = "Compute for the Streamlit / Native App UI."
}

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------
variable "role_admin" {
  type        = string
  description = "Agent-scoped admin role (hierarchy root of the demo roles)."
}

variable "role_engineer" {
  type        = string
  description = "Functional role for pipeline creation (dbt, Snowpipe, Snowpark)."
}

variable "role_analyst" {
  type        = string
  description = "Functional role used to demonstrate masked/RLS-restricted access."
}

# ---------------------------------------------------------------------------
# Governance object names (inside schema_governance)
# ---------------------------------------------------------------------------
variable "masking_policy_national_id" {
  type        = string
  description = "Masking policy for CLIENT_PROFILE_DIM.RUT (national ID)."
}

variable "masking_policy_credit_card" {
  type        = string
  description = "Masking policy for CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA."
}

variable "row_access_policy_name" {
  type        = string
  description = "Row access policy filtering rows by business unit."
}

variable "rls_mapping_table" {
  type        = string
  description = "Role-to-business-unit mapping table consumed by the row access policy."
}

# ---------------------------------------------------------------------------
# Behaviour toggles
# ---------------------------------------------------------------------------
variable "operator_user" {
  type        = string
  description = "Snowflake user (service/presenter account) granted FR_DEMO_ADMIN so it can assume the demo roles."
  default     = "OPERATIONS"
}
variable "attach_policies_to_tables" {
  type        = bool
  description = <<-EOT
    Attach masking policies to the demo tables. Must be false on the initial
    apply (tables are created later by the session data scripts) and switched
    to true after Session 1 data load for the Session 3 governance demo.
  EOT
  default     = false
}
