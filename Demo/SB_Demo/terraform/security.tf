# ============================================================================
# Snowflake Platform Demo — Security (Roles, Hierarchy, RBAC Grants)
# ============================================================================
# Hierarchy:  FR_DEMO_ADMIN
#               ├── FR_DATA_ENGINEER
#               └── FR_BI_ANALYST
#
# Least privilege: the engineer builds, the analyst reads (masked), the admin
# orchestrates. No demo role receives ACCOUNTADMIN.
# ============================================================================

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------
resource "snowflake_account_role" "admin" {
  name    = var.role_admin
  comment = "Agent-scoped admin role — hierarchy root of the demo roles."
}

resource "snowflake_account_role" "engineer" {
  name    = var.role_engineer
  comment = "Pipeline creation: dbt, Snowpipe, Snowpark."
}

resource "snowflake_account_role" "analyst" {
  name    = var.role_analyst
  comment = "Read-only persona used to demonstrate masking and row-level security."
}

# ---------------------------------------------------------------------------
# Role hierarchy
# ---------------------------------------------------------------------------
resource "snowflake_grant_account_role" "engineer_to_admin" {
  role_name        = snowflake_account_role.engineer.name
  parent_role_name = snowflake_account_role.admin.name
}

resource "snowflake_grant_account_role" "analyst_to_admin" {
  role_name        = snowflake_account_role.analyst.name
  parent_role_name = snowflake_account_role.admin.name
}

# The operator user receives the hierarchy root and can therefore USE
# FR_DATA_ENGINEER / FR_BI_ANALYST through role inheritance.
resource "snowflake_grant_account_role" "operator_admin" {
  role_name = snowflake_account_role.admin.name
  user_name = var.operator_user
}

# ---------------------------------------------------------------------------
# FR_DEMO_ADMIN — database, schemas, warehouses, policy authoring
# ---------------------------------------------------------------------------
resource "snowflake_grant_privileges_to_account_role" "admin_db_usage" {
  account_role_name = snowflake_account_role.admin.name
  # CREATE SCHEMA is a DATABASE-level privilege, not a schema-level one.
  privileges = ["USAGE", "MONITOR", "CREATE SCHEMA"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_all_schemas" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["USAGE", "MONITOR"]
  on_schema {
    all_schemas_in_database = snowflake_database.demo.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_wh_ingestion" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["USAGE", "MONITOR"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.ingestion.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_wh_cortex" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["USAGE", "MONITOR"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.cortex.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_wh_app" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["USAGE", "MONITOR"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.app.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_policy_authoring" {
  account_role_name = snowflake_account_role.admin.name
  privileges = [
    "CREATE MASKING POLICY",
    "CREATE ROW ACCESS POLICY",
    "CREATE TAG",
  ]
  on_schema {
    schema_name = snowflake_schema.governance.fully_qualified_name
  }
}

# Session 3 — the admin verifies unmasked data and seeds/reads ROLE_MAPPING:
# MODIFY on core enables ALTER TABLE ... ADD/DROP ROW ACCESS POLICY (the RLS
# binding is executed by the Session 3 script — the provider has no resource
# for it), SELECT lets the admin query the marts plaintext for the demo.
resource "snowflake_grant_privileges_to_account_role" "admin_core_modify" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["MODIFY"]
  on_schema {
    schema_name = snowflake_schema.core.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_core_select_all" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.core.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_core_select_future" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      in_schema          = snowflake_schema.core.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

# Session 3 — Horizon object tagging: no APPLY TAG grant is needed here —
# APPLY TAG exists only as an account-level privilege (granting it ON SCHEMA
# or ON DATABASE fails 003008), and Snowflake lets a role that holds MODIFY on
# the table (FR_DEMO_ADMIN via admin_core_modify) tag its columns directly —
# verified with sql/03_object_tagging_demo.sql. CREATE TAG on GOVERNANCE_SCHEMA
# comes from admin_policy_authoring above.

resource "snowflake_grant_privileges_to_account_role" "admin_governance_dml_all" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.governance.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_governance_dml_future" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["SELECT", "INSERT", "UPDATE", "DELETE"]
  on_schema_object {
    future {
      in_schema          = snowflake_schema.governance.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

# NOTE — APPLY MASKING POLICY and APPLY ROW ACCESS POLICY exist only as
# account-level (global) privileges (granting them ON SCHEMA fails 003008),
# and FR_TERRAFORM cannot grant account-level privileges (003102) — Snowflake
# checks granter authorization even for idempotent GRANTs. These two grants
# are therefore a manual bootstrap step executed once as ACCOUNTADMIN
# (documented in phase3-next-steps.md); Terraform does not manage them.

# ---------------------------------------------------------------------------
# FR_DATA_ENGINEER — build in raw / staging / analytics layers
# ---------------------------------------------------------------------------
resource "snowflake_grant_privileges_to_account_role" "engineer_db_usage" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_core_build" {
  account_role_name = snowflake_account_role.engineer.name
  # CREATE ICEBERG TABLE is a distinct schema privilege (Session 1 lakehouse demo).
  privileges = ["USAGE", "CREATE TABLE", "CREATE ICEBERG TABLE", "CREATE VIEW", "MODIFY", "ADD SEARCH OPTIMIZATION"]
  on_schema {
    schema_name = snowflake_schema.core.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_staging_build" {
  account_role_name = snowflake_account_role.engineer.name
  # CREATE FILE FORMAT + CREATE STAGE enable the raw COPY INTO ingestion.
  privileges = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE FILE FORMAT", "CREATE STAGE", "MODIFY", "ADD SEARCH OPTIMIZATION"]
  on_schema {
    schema_name = snowflake_schema.staging.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_analytics_build" {
  account_role_name = snowflake_account_role.engineer.name
  # CREATE MODEL (+ CREATE FUNCTION for the model's generated inference
  # functions) lets the engineer register models in the Model Registry.
  privileges = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE MODEL", "CREATE FUNCTION", "MODIFY", "ADD SEARCH OPTIMIZATION"]
  on_schema {
    schema_name = snowflake_schema.analytics.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_governance_read" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.governance.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_wh_ingestion" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.ingestion.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_wh_cortex" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.cortex.name
  }
}

# The engineer executes ML inference and deploys the demo Streamlit app.
resource "snowflake_grant_privileges_to_account_role" "engineer_wh_app" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.app.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_native_app_usage" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.native_app.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_native_app_streamlit" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE", "CREATE STREAMLIT"]
  on_schema {
    schema_name = "${snowflake_database.native_app.name}.PUBLIC"
  }
}

# PUT of streamlit_app.py into the app stage (presenter step, human-approved).
resource "snowflake_grant_privileges_to_account_role" "engineer_native_app_stage_rw" {
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["READ", "WRITE"]
  on_schema_object {
    object_type = "STAGE"
    object_name = snowflake_stage.streamlit.fully_qualified_name
  }
}

# ---------------------------------------------------------------------------
# FR_BI_ANALYST — read-only (masking/RLS apply at query time)
# ---------------------------------------------------------------------------
resource "snowflake_grant_privileges_to_account_role" "analyst_db_usage" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_core_read" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.core.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_core_select_all" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.core.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_core_select_future" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      in_schema          = snowflake_schema.core.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_staging_read" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.staging.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_staging_select_all" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.staging.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_staging_select_future" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      in_schema          = snowflake_schema.staging.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_analytics_read" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.analytics.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_analytics_select_all" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.analytics.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_analytics_select_future" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      in_schema          = snowflake_schema.analytics.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_wh_cortex" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.cortex.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_wh_app" {
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.app.name
  }
}
