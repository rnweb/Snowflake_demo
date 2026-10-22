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
  description = "Curated dbt models, aggregated entities, and governed data (Silver/Gold)"
}

variable "schema_analytics" {
  type        = string
  description = "Data Science workspaces and Snowpark ML models"
}

variable "schema_staging" {
  type        = string
  description = "Raw ingestion layer and Iceberg external tables (Bronze)"
}

variable "schema_governance" {
  type        = string
  description = "Masking/row-access policies and role-mapping tables."
}

variable "schema_vector_store" {
  type        = string
  description = "Vector store schema for Cortex embeddings and RAG document retrieval."
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
  description = "Masking policy for RUT (national ID) on CLIENT_PROFILE_DIM and CREDIT_CARD_TRANSACTIONS; deterministic pseudonym for non-admin roles."
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

# ---------------------------------------------------------------------------
# External integrations (integrations.tf) — IDMC CDI, IDMC CDGC, Power BI
# ---------------------------------------------------------------------------
variable "schema_idmc_landing" {
  type        = string
  description = "Landing schema for IDMC CDI loads."
  default     = "IDMC_LANDING_SCHEMA"
}

variable "role_idmc_integration" {
  type        = string
  description = "Service role for the IDMC CDI connection."
  default     = "FR_IDMC_INTEGRATION"
}

variable "role_catalog_reader" {
  type        = string
  description = "Service role for the IDMC CDGC catalog source."
  default     = "FR_CATALOG_READER"
}

variable "create_integration_users" {
  type        = bool
  description = "Create the IDMC and Power BI users. Requires CREATE USER on FR_TERRAFORM (bootstrap) and the passwords below."
  default     = true
}

variable "user_idmc_cdi" {
  type    = string
  default = "SVC_IDMC_CDI"
}

variable "user_idmc_cdgc" {
  type    = string
  default = "SVC_IDMC_CDGC"
}

variable "user_bi_analyst" {
  type    = string
  default = "DEMO_ANALYST"
}

# Secrets: set via TF_VAR_<name> environment variables, never in tfvars.
variable "idmc_cdi_password" {
  type      = string
  sensitive = true
  default   = null
}

variable "idmc_cdgc_password" {
  type      = string
  sensitive = true
  default   = null
}

variable "bi_analyst_password" {
  type      = string
  sensitive = true
  default   = null
}

# Optional key-pair auth (public key body, no BEGIN/END lines).
variable "idmc_cdi_rsa_public_key" {
  type    = string
  default = null
}

variable "idmc_cdgc_rsa_public_key" {
  type    = string
  default = null
}

variable "bi_analyst_rsa_public_key" {
  type    = string
  default = null
}
