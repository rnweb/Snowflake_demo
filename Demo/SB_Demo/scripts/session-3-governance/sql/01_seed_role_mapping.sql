-- =============================================================================
-- Session 3 — 01: Seed ROLE_MAPPING + bind the row access policy
-- =============================================================================
-- Rol: FR_DEMO_ADMIN | Almacén: WH_APP_MEDIUM
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
--   FR_IDMC_INTEGRATION / FR_CATALOG_READER -> all units (IDMC CDI / CDGC)
--   FR_EXTERNAL_READER -> PYME (C08); FR_DATA_SCIENTIST -> all units (PG-08)
--   FR_TENANT_RIESGO -> all units, FR_TENANT_FRAUDE -> PYME (PG-17)
--   FR_DEMO_ADMIN / ACCOUNTADMIN bypass the policy entirely (policy body).
--   Re-seeding is now safe: every role used by the demo is listed here.
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
    ('FR_DATA_ENGINEER', 'RETAIL', 'Persona ingeniera — acceso completo (pipeline dbt/ML)'),
    -- External integrations (terraform/integrations.tf): without these rows the
    -- policy returns ZERO rows, silently, to IDMC CDI and IDMC CDGC.
    ('FR_IDMC_INTEGRATION', 'PYME', 'IDMC CDI — integración (acceso completo)'),
    ('FR_IDMC_INTEGRATION', 'CORPORATIVO', 'IDMC CDI — integración (acceso completo)'),
    ('FR_IDMC_INTEGRATION', 'RETAIL', 'IDMC CDI — integración (acceso completo)'),
    ('FR_CATALOG_READER', 'PYME', 'IDMC CDGC — catálogo y perfilamiento'),
    ('FR_CATALOG_READER', 'CORPORATIVO', 'IDMC CDGC — catálogo y perfilamiento'),
    ('FR_CATALOG_READER', 'RETAIL', 'IDMC CDGC — catálogo y perfilamiento'),
    -- C08 external consumer via Data Marketplace (role from session-3/05, block 0)
    ('FR_EXTERNAL_READER', 'PYME', 'External consumer via Data Marketplace'),
    -- PG-08 data-scientist persona (session-3/07): full rows, masked PII
    ('FR_DATA_SCIENTIST', 'PYME', 'Persona científica de datos — filas completas, PII enmascarada'),
    ('FR_DATA_SCIENTIST', 'CORPORATIVO', 'Persona científica de datos — filas completas, PII enmascarada'),
    ('FR_DATA_SCIENTIST', 'RETAIL', 'Persona científica de datos — filas completas, PII enmascarada'),
    -- PG-17 tenants (session-5/01): Riesgo sees all units, Fraude only PYME
    ('FR_TENANT_RIESGO', 'PYME', 'Tenant Riesgo (PG-17)'),
    ('FR_TENANT_RIESGO', 'CORPORATIVO', 'Tenant Riesgo (PG-17)'),
    ('FR_TENANT_RIESGO', 'RETAIL', 'Tenant Riesgo (PG-17)'),
    ('FR_TENANT_FRAUDE', 'PYME', 'Tenant Fraude (PG-17)');

-- -----------------------------------------------------------------------------
-- 2. Verify the seed (18 rows expected)
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
