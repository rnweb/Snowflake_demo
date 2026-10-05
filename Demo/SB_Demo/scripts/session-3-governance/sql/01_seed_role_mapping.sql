-- =============================================================================
-- Session 3 — 01: Seed ROLE_MAPPING + bind the row access policy
-- =============================================================================
-- Rol: FR_DEMO_ADMIN | Almacén: WH_APP_XSMALL
--
-- Purpose: mapping-table rows and the ALTER TABLE ... ADD ROW ACCESS POLICY
-- binding live in SQL (data stays out of Terraform); the policy object itself
-- is Terraform-managed (terraform/governance.tf). Run AFTER
-- `terraform apply` with attach_policies_to_tables = true.
--
-- Re-runs: the seed DELETEs + re-INSERTs. The binding in step 3 is one-shot —
-- if the policy is already attached, only that last statement errors
-- ("already exists") and the rest of the script still succeeds.
--
-- Expected after the seed:
--   FR_BI_ANALYST    -> RETAIL only        (analyst persona)
--   FR_DATA_ENGINEER -> PYME/CORPORATIVO/RETAIL (dbt + ML keep full access)
--   FR_DEMO_ADMIN / ACCOUNTADMIN bypass the policy entirely (policy body).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Seed the role -> business-unit mapping
-- -----------------------------------------------------------------------------
DELETE FROM SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING;

INSERT INTO SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING
    (ROLE_NAME, BUSINESS_UNIT, DESCRIPTION)
VALUES
    ('FR_BI_ANALYST', 'RETAIL', 'Persona analista — solo ve la unidad de negocio RETAIL'),
    ('FR_DATA_ENGINEER', 'PYME', 'Persona ingeniera — acceso completo (pipeline dbt/ML)'),
    ('FR_DATA_ENGINEER', 'CORPORATIVO', 'Persona ingeniera — acceso completo (pipeline dbt/ML)'),
    ('FR_DATA_ENGINEER', 'RETAIL', 'Persona ingeniera — acceso completo (pipeline dbt/ML)');

-- -----------------------------------------------------------------------------
-- 2. Verify the seed (4 rows expected)
-- -----------------------------------------------------------------------------
SELECT ROLE_NAME, BUSINESS_UNIT, DESCRIPTION
FROM SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING
ORDER BY ROLE_NAME, BUSINESS_UNIT;

-- -----------------------------------------------------------------------------
-- 3. Bind the row access policy (no Terraform resource exists for this ALTER)
-- -----------------------------------------------------------------------------
ALTER TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
    ADD ROW ACCESS POLICY SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.RLS_BUSINESS_UNIT
    ON (UNIDAD_NEGOCIO);
