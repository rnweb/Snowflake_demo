# ============================================================================
# Snowflake Platform Demo — External Integrations (IDMC CDI, IDMC CDGC, Power BI)
# ============================================================================
# One dedicated user + least-privilege role per external tool, so ACCESS_HISTORY
# and QUERY_HISTORY show which tool did what (C08-AE-04) and no tool inherits
# admin privileges through secondary roles.
#
#   Tool          User                 Role                  Warehouse
#   IDMC CDI      var.user_idmc_cdi     FR_IDMC_INTEGRATION   WH_INGESTION_MEDIUM
#   IDMC CDGC     var.user_idmc_cdgc    FR_CATALOG_READER     WH_APP_MEDIUM
#   Power BI      var.user_bi_analyst   FR_BI_ANALYST (exists) WH_APP_MEDIUM
#
# Hierarchy:  FR_DEMO_ADMIN
#               ├── FR_IDMC_INTEGRATION   (writes only to IDMC_LANDING_SCHEMA)
#               └── FR_CATALOG_READER     (metadata everywhere; data only from
#                                          masked layers)
#
# Row access: RLS_BUSINESS_UNIT returns ZERO rows (no error) for any non-admin
# role missing from ROLE_MAPPING. Both new roles are seeded in
# scripts/session-3-governance/sql/01_seed_role_mapping.sql.
#
# Passwords: supplied only through environment variables
# (TF_VAR_idmc_cdi_password, TF_VAR_idmc_cdgc_password, TF_VAR_bi_analyst_password).
# They are marked sensitive but DO end up in the state file, which is
# git-ignored. Optional key-pair auth: set the *_rsa_public_key variables.
#
# Bootstrap (ACCOUNTADMIN, once per account — see scripts/bootstrap/
# 00_accountadmin_bootstrap.sql): FR_TERRAFORM needs CREATE USER, and the
# catalog role needs the SNOWFLAKE.GOVERNANCE_VIEWER database role.
# ============================================================================

# ---------------------------------------------------------------------------
# Landing schema for IDMC CDI loads (kept apart from dbt-managed schemas)
# ---------------------------------------------------------------------------
resource "snowflake_schema" "idmc_landing" {
  database = snowflake_database.demo.name
  name     = var.schema_idmc_landing
  comment  = "Landing zone for Informatica IDMC CDI loads (external integration, C03)."
}

# ---------------------------------------------------------------------------
# Roles + hierarchy
# ---------------------------------------------------------------------------
resource "snowflake_account_role" "idmc_integration" {
  name    = var.role_idmc_integration
  comment = "IDMC CDI service role: writes to the landing schema, reads the curated (masked) layer."
}

resource "snowflake_account_role" "catalog_reader" {
  name    = var.role_catalog_reader
  comment = "IDMC CDGC service role: metadata extraction everywhere, profiling only on masked layers."
}

resource "snowflake_grant_account_role" "idmc_integration_to_admin" {
  role_name        = snowflake_account_role.idmc_integration.name
  parent_role_name = snowflake_account_role.admin.name
}

resource "snowflake_grant_account_role" "catalog_reader_to_admin" {
  role_name        = snowflake_account_role.catalog_reader.name
  parent_role_name = snowflake_account_role.admin.name
}

# FR_DEMO_ADMIN can read what IDMC lands (demo validation).
resource "snowflake_grant_privileges_to_account_role" "admin_idmc_landing_select_future" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      in_schema          = snowflake_schema.idmc_landing.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

# ---------------------------------------------------------------------------
# FR_IDMC_INTEGRATION — IDMC CDI
# ---------------------------------------------------------------------------
resource "snowflake_grant_privileges_to_account_role" "idmc_wh_ingestion" {
  account_role_name = snowflake_account_role.idmc_integration.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.ingestion.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "idmc_db_usage" {
  account_role_name = snowflake_account_role.idmc_integration.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo.name
  }
}

# Pushdown and bulk load create temporary tables, views, stages and file
# formats in the connection's default schema.
resource "snowflake_grant_privileges_to_account_role" "idmc_landing_build" {
  account_role_name = snowflake_account_role.idmc_integration.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE STAGE", "CREATE FILE FORMAT", "CREATE SEQUENCE"]
  on_schema {
    schema_name = snowflake_schema.idmc_landing.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "idmc_core_usage" {
  account_role_name = snowflake_account_role.idmc_integration.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.core.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "idmc_core_select_all" {
  account_role_name = snowflake_account_role.idmc_integration.name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.core.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "idmc_core_select_future" {
  account_role_name = snowflake_account_role.idmc_integration.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      in_schema          = snowflake_schema.core.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

# ---------------------------------------------------------------------------
# FR_CATALOG_READER — IDMC CDGC
# ---------------------------------------------------------------------------
resource "snowflake_grant_privileges_to_account_role" "catalog_wh_app" {
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.app.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "catalog_db_usage" {
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "catalog_all_schemas" {
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["USAGE"]
  on_schema {
    all_schemas_in_database = snowflake_database.demo.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "catalog_future_schemas" {
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["USAGE"]
  on_schema {
    future_schemas_in_database = snowflake_database.demo.name
  }
}

# Bronze: structure only. Raw tables carry no masking, so the catalog must not
# profile them (it would copy plaintext RUT / card numbers into CDGC).
resource "snowflake_grant_privileges_to_account_role" "catalog_staging_refs_tables" {
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["REFERENCES"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.staging.fully_qualified_name
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "catalog_staging_refs_views" {
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["REFERENCES"]
  on_schema_object {
    all {
      in_schema          = snowflake_schema.staging.fully_qualified_name
      object_type_plural = "VIEWS"
    }
  }
}

# Silver/Gold, Data Science and IDMC landing: SELECT for profiling. Policies
# use CURRENT_ROLE(), so profiles come back masked — a demo talking point.
locals {
  catalog_select_schemas = {
    core      = snowflake_schema.core.fully_qualified_name
    analytics = snowflake_schema.analytics.fully_qualified_name
    landing   = snowflake_schema.idmc_landing.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "catalog_select_all" {
  for_each          = local.catalog_select_schemas
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["SELECT"]
  on_schema_object {
    all {
      in_schema          = each.value
      object_type_plural = "TABLES"
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "catalog_select_future" {
  for_each          = local.catalog_select_schemas
  account_role_name = snowflake_account_role.catalog_reader.name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      in_schema          = each.value
      object_type_plural = "TABLES"
    }
  }
}

# ---------------------------------------------------------------------------
# Users (PERSON type: Standard auth with password, optional key pair)
# ---------------------------------------------------------------------------
resource "snowflake_user" "idmc_cdi" {
  count                          = var.create_integration_users ? 1 : 0
  name                           = var.user_idmc_cdi
  comment                        = "Informatica IDMC CDI connection user (SB demo)."
  password                       = var.idmc_cdi_password
  rsa_public_key                 = var.idmc_cdi_rsa_public_key
  default_role                   = snowflake_account_role.idmc_integration.name
  default_warehouse              = snowflake_warehouse.ingestion.name
  default_namespace              = snowflake_schema.idmc_landing.fully_qualified_name
  default_secondary_roles_option = "NONE"
  must_change_password           = "false"
}

resource "snowflake_user" "idmc_cdgc" {
  count                          = var.create_integration_users ? 1 : 0
  name                           = var.user_idmc_cdgc
  comment                        = "Informatica IDMC CDGC catalog source user (SB demo)."
  password                       = var.idmc_cdgc_password
  rsa_public_key                 = var.idmc_cdgc_rsa_public_key
  default_role                   = snowflake_account_role.catalog_reader.name
  default_warehouse              = snowflake_warehouse.app.name
  default_secondary_roles_option = "NONE"
  must_change_password           = "false"
}

resource "snowflake_user" "bi_analyst" {
  count                          = var.create_integration_users ? 1 : 0
  name                           = var.user_bi_analyst
  comment                        = "Power BI consumer persona: FR_BI_ANALYST only (masked PII, RETAIL rows)."
  password                       = var.bi_analyst_password
  rsa_public_key                 = var.bi_analyst_rsa_public_key
  default_role                   = snowflake_account_role.analyst.name
  default_warehouse              = snowflake_warehouse.app.name
  default_secondary_roles_option = "NONE"
  must_change_password           = "false"
}

resource "snowflake_grant_account_role" "idmc_cdi_user" {
  count     = var.create_integration_users ? 1 : 0
  role_name = snowflake_account_role.idmc_integration.name
  user_name = snowflake_user.idmc_cdi[0].name
}

resource "snowflake_grant_account_role" "idmc_cdgc_user" {
  count     = var.create_integration_users ? 1 : 0
  role_name = snowflake_account_role.catalog_reader.name
  user_name = snowflake_user.idmc_cdgc[0].name
}

resource "snowflake_grant_account_role" "bi_analyst_user" {
  count     = var.create_integration_users ? 1 : 0
  role_name = snowflake_account_role.analyst.name
  user_name = snowflake_user.bi_analyst[0].name
}
