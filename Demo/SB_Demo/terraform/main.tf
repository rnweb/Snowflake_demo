# ============================================================================
# Snowflake Platform Demo — Infrastructure (Databases, Schemas, Warehouses)
# ============================================================================

# ---------------------------------------------------------------------------
# Databases
# ---------------------------------------------------------------------------
resource "snowflake_database" "demo" {
  name = var.demo_db_name
}

# Native Apps require the application package to live in its own database.
resource "snowflake_database" "native_app" {
  name = var.native_app_db_name
}

# ---------------------------------------------------------------------------
# Schemas — primary demo database
# ---------------------------------------------------------------------------
resource "snowflake_schema" "core" {
  database = snowflake_database.demo.name
  name     = var.schema_core
  comment  = "Curated dbt models, aggregated entities, and governed data (Silver/Gold)"
}

resource "snowflake_schema" "analytics" {
  database = snowflake_database.demo.name
  name     = var.schema_analytics
  comment  = "Data Science workspaces and Snowpark ML models"
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.demo.name
  name     = var.schema_staging
  comment  = "Raw ingestion layer and Iceberg external tables (Bronze)"
}

resource "snowflake_schema" "governance" {
  database = snowflake_database.demo.name
  name     = var.schema_governance
  comment  = "Masking/row-access policies and role-mapping tables."
}

resource "snowflake_schema" "vector_store" {
  database = snowflake_database.demo.name
  name     = var.schema_vector_store
  comment  = "Cortex vector store: embeddings, document chunks and RAG retrieval context."
}

# ---------------------------------------------------------------------------
# External access (Session 4 - Integraciones y APIs / C03)
# Egress allow-list + integration so SP_INGEST_EXTERNAL_API (bronze loader)
# can reach the public FX-rates API. The engineer USAGE grant lives in
# security.tf; the procedure itself is created by the Session 4 SQL script.
# ---------------------------------------------------------------------------
resource "snowflake_network_rule" "api_currency_rule" {
  name       = "API_CURRENCY_NETWORK_RULE"
  database   = snowflake_database.demo.name
  schema     = snowflake_schema.staging.name
  type       = "HOST_PORT"
  mode       = "EGRESS"
  value_list = ["api.frankfurter.app"]
}

resource "snowflake_external_access_integration" "api_currency_integration" {
  name                  = "API_CURRENCY_INTEGRATION"
  enabled               = true
  allowed_network_rules = [snowflake_network_rule.api_currency_rule.fully_qualified_name]
}

# ---------------------------------------------------------------------------
# Warehouses
# ---------------------------------------------------------------------------
resource "snowflake_warehouse" "ingestion" {
  name                         = var.wh_ingestion
  comment                      = "Snowpipe and dbt runs."
  warehouse_size               = "XSMALL"
  auto_suspend                 = 60
  auto_resume                  = true
  initially_suspended          = true
  statement_timeout_in_seconds = 300
}

resource "snowflake_warehouse" "cortex" {
  name                         = var.wh_cortex
  comment                      = "ML training and Cortex LLM queries."
  warehouse_size               = "LARGE"
  auto_suspend                 = 120
  auto_resume                  = true
  initially_suspended          = true
  statement_timeout_in_seconds = 600
}

resource "snowflake_warehouse" "app" {
  name                         = var.wh_app
  comment                      = "Streamlit / Native App UI compute."
  warehouse_size               = "XSMALL"
  auto_suspend                 = 60
  auto_resume                  = true
  initially_suspended          = true
  statement_timeout_in_seconds = 300
}

# ---------------------------------------------------------------------------
# App staging area — holds streamlit_app.py until the presenter deploys it
# ---------------------------------------------------------------------------
resource "snowflake_stage" "streamlit" {
  name     = "STREAMLIT_STAGE"
  database = snowflake_database.native_app.name
  schema   = "PUBLIC"
  comment  = "Source files for the Panel de Prevención de Fraude Streamlit app."
}
