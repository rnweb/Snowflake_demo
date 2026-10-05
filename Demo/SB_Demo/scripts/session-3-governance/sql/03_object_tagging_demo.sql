-- =============================================================================
-- Session 3 — 03: Horizon object-tagging demo (PII classification)
-- =============================================================================
-- Rol: FR_DEMO_ADMIN | Almacén: WH_APP_XSMALL
--
-- Purpose: tag the PII columns so they are discoverable in Snowsight's Data
-- Governance Center (Object Tagging) — the Horizon complement to the masking
-- policies attached by Terraform. Re-runnable (IF NOT EXISTS / re-SET).
--
-- Prerequisites: terraform apply (admin_core_apply_tag grant) — CREATE TAG on
-- GOVERNANCE_SCHEMA + APPLY TAG / MODIFY on CORE_BANKING_SCHEMA.
-- =============================================================================

-- 1. Classification tag (single source for the PII label)
CREATE TAG IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.DATA_CLASSIFICATION
    COMMENT = 'Clasificacion de datos sensibles (PII) — demo Horizon de la Superintendencia';

-- 2. Tag the PII columns (same columns that carry the masking policies)
ALTER TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
    MODIFY COLUMN RUT
    SET TAG SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.DATA_CLASSIFICATION = 'PII';

ALTER TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
    MODIFY COLUMN NUMERO_TARJETA
    SET TAG SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.DATA_CLASSIFICATION = 'PII';

-- 3. Verify: both columns must report tag PII (Snowsight: Data -> Governance
--    -> Object Tagging shows the same result)
SELECT OBJECT_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.TAG_REFERENCES(
    'SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM.RUT', 'COLUMN'))
UNION ALL
SELECT OBJECT_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.TAG_REFERENCES(
    'SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA', 'COLUMN'))
ORDER BY OBJECT_NAME;
