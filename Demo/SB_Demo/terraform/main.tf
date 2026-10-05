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
  comment  = "Raw ingestion layer for transactional data."
}

resource "snowflake_schema" "analytics" {
  database = snowflake_database.demo.name
  name     = var.schema_analytics
  comment  = "Transformed layer for BI, RLS, and Cortex."
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.demo.name
  name     = var.schema_staging
  comment  = "dbt intermediate layer."
}

resource "snowflake_schema" "governance" {
  database = snowflake_database.demo.name
  name     = var.schema_governance
  comment  = "Masking/row-access policies and role-mapping tables."
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
