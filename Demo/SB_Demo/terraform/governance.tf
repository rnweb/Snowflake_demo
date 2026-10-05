# ============================================================================
# Snowflake Platform Demo — Data Governance (Masking & Row-Level Security)
# ============================================================================
# Objects live in <demo_db>.<schema_governance> (see terraform.tfvars).
#
# Pattern demonstrated in Session 3:
#   * Dynamic Data Masking on PII columns (NATIONAL_ID, CREDIT_CARD_NUMBER)
#   * Row-Level Security via a role -> business-unit mapping table
#   * Admin roles see plaintext; FR_BI_ANALYST sees masked/filtered data
# ============================================================================

# ---------------------------------------------------------------------------
# Masking policies
# ---------------------------------------------------------------------------
resource "snowflake_masking_policy" "national_id" {
  name     = var.masking_policy_national_id
  database = snowflake_database.demo.name
  schema   = snowflake_schema.governance.name
  comment  = "Masks NATIONAL_ID — plaintext for admin roles only."

  argument {
    name = "val"
    type = "VARCHAR"
  }

  body = <<-SQL
    case
      when current_role() in ('${var.role_admin}', 'ACCOUNTADMIN') then val
      else '***-**-****'
    end
  SQL

  return_data_type = "VARCHAR"
}

resource "snowflake_masking_policy" "credit_card" {
  name     = var.masking_policy_credit_card
  database = snowflake_database.demo.name
  schema   = snowflake_schema.governance.name
  comment  = "Masks CREDIT_CARD_NUMBER — plaintext for admin roles only."

  argument {
    name = "val"
    type = "VARCHAR"
  }

  body = <<-SQL
    case
      when current_role() in ('${var.role_admin}', 'ACCOUNTADMIN') then val
      else '****-****-****-****'
    end
  SQL

  return_data_type = "VARCHAR"
}

# ---------------------------------------------------------------------------
# Row access policy + mapping table
# ---------------------------------------------------------------------------
resource "snowflake_table" "rls_mapping" {
  database = snowflake_database.demo.name
  schema   = snowflake_schema.governance.name
  name     = var.rls_mapping_table
  comment  = "Role -> business unit mapping consumed by the RLS policy. Rows are loaded by the Session 3 script (data stays out of Terraform)."

  column {
    name = "ROLE_NAME"
    type = "VARCHAR(255)"
  }

  column {
    name = "BUSINESS_UNIT"
    type = "VARCHAR(255)"
  }

  column {
    name = "DESCRIPTION"
    type = "VARCHAR(255)"
  }
}

resource "snowflake_row_access_policy" "business_unit" {
  name     = var.row_access_policy_name
  database = snowflake_database.demo.name
  schema   = snowflake_schema.governance.name
  comment  = "Filters rows by business unit for non-admin roles via the ROLE_MAPPING table."

  # The policy body contains a subquery against ROLE_MAPPING; Snowflake
  # resolves it at CREATE time, so the table must exist first.
  depends_on = [snowflake_table.rls_mapping]

  argument {
    name = "business_unit"
    type = "VARCHAR"
  }

  body = <<-SQL
    case
      when current_role() in ('${var.role_admin}', 'ACCOUNTADMIN') then true
      else exists (
        select 1
        from ${snowflake_database.demo.name}.${snowflake_schema.governance.name}.${var.rls_mapping_table} m
        where m.role_name = current_role()
          and m.business_unit = business_unit
      )
    end
  SQL
}

# ---------------------------------------------------------------------------
# Policy attachment to demo tables (Session 3 activation switch)
# ---------------------------------------------------------------------------
# Tables are created by the session data scripts (scripts/session-1-lakehouse),
# not by Terraform. Flip attach_policies_to_tables to true in terraform.tfvars
# AFTER the data load, then re-run `terraform apply` for the governance demo.
#
# The aliased provider (providers.tf) executes these ALTERs as FR_DEMO_ADMIN,
# the only non-system role holding the account-level APPLY MASKING POLICY
# privilege — see the provider comment for the full rationale.

resource "snowflake_table_column_masking_policy_application" "national_id" {
  provider = snowflake.policy_author
  count    = var.attach_policies_to_tables ? 1 : 0

  table          = "${var.demo_db_name}.${var.schema_core}.CLIENT_PROFILE_DIM"
  column         = "RUT"
  masking_policy = snowflake_masking_policy.national_id.fully_qualified_name
}

resource "snowflake_table_column_masking_policy_application" "credit_card" {
  provider = snowflake.policy_author
  count    = var.attach_policies_to_tables ? 1 : 0

  table          = "${var.demo_db_name}.${var.schema_core}.CREDIT_CARD_TRANSACTIONS"
  column         = "NUMERO_TARJETA"
  masking_policy = snowflake_masking_policy.credit_card.fully_qualified_name
}

# NOTE — Row access policy attachment:
# the provider has no resource for `ALTER TABLE ... ADD ROW ACCESS POLICY`;
# the binding is executed by the Session 3 script after tables exist:
#   ALTER TABLE <demo_db>.<schema_core>.CREDIT_CARD_TRANSACTIONS
#     ADD ROW ACCESS POLICY <demo_db>.<schema_governance>.RLS_BUSINESS_UNIT
#     ON (UNIDAD_NEGOCIO);
# The policy object itself (defined above) remains fully Terraform-managed.
