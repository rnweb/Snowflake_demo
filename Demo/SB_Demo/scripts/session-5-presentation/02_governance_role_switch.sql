-- =============================================================================
-- Session 5 — 02: Governance drill-down (same SQL, two roles)
-- =============================================================================
-- Role pair: FR_DEMO_ADMIN (admin) vs FR_BI_ANALYST (analyst) · Warehouse:
-- WH_APP_MEDIUM · Mart: SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.
--
-- How to present: run the WHOLE file in one worksheet (it switches roles
-- mid-way). Scroll side-by-side: section A (admin) and section B (analyst)
-- execute the IDENTICAL SQL — zero application changes.
--
-- PRESENTER — the three beats of this script:
--   1. Identity: CURRENT_ROLE() differs; everything else is the same table.
--   2. Masking (column level): RUT -> deterministic pseudonym
--      '***-**-<12 hex>' (same token every time), NUMERO_TARJETA ->
--      '****-****-****-****'. Admins bypass both policies.
--   3. Row-level security (row level): RLS_BUSINESS_UNIT filters by the
--      role -> business-unit mapping. Analyst = RETAIL only
--      (15 969 793 of 50 000 000 rows). The WHERE in section B proves the
--      pseudonym still filters correctly (deterministic mask by design —
--      predicates run on the post-policy value).
--
-- Persona isolation: every section starts with USE SECONDARY ROLES NONE.
-- The operator user also holds other roles and Snowflake keeps a user's
-- roles active as secondaries by default — without the isolation the
-- analyst section would silently inherit admin privileges.
--
-- Expected results:
--   A. FR_DEMO_ADMIN -> RUT y tarjeta EN CLARO (p. ej. 5.030.068-4 /
--      5500-...), 3 unidades (50 000 000 filas), ROLE_MAPPING 4+ filas
--   B. FR_BI_ANALYST -> RUT ***-**-<12 hex> (token idéntico al de la dim),
--      tarjeta ****-****-****-****, SOLO RETAIL (15 969 793 filas),
--      filtro por token devuelve > 0 filas
-- Full narrative + policy DDL: scripts/session-3-governance/README.md
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A. FR_DEMO_ADMIN — plaintext PII, all business units
-- -----------------------------------------------------------------------------
USE ROLE FR_DEMO_ADMIN;
USE SECONDARY ROLES NONE;  -- isolate: only FR_DEMO_ADMIN is effective
USE WAREHOUSE WH_APP_MEDIUM;
USE DATABASE SUPERINTENDENCY_DEMO_DB;
USE SCHEMA CORE_BANKING_SCHEMA;

SELECT CURRENT_ROLE() AS ROL_ACTIVO, CURRENT_USER() AS USUARIO;

-- Identical query both sections — note it in the narration before running B.
SELECT
    RUT,
    NUMERO_TARJETA,
    CATEGORIA,
    MONTO,
    ESTADO,
    UNIDAD_NEGOCIO
FROM CREDIT_CARD_TRANSACTIONS
ORDER BY MONTO DESC
LIMIT 5;

SELECT
    UNIDAD_NEGOCIO,
    COUNT(*) AS TRANSACCIONES
FROM CREDIT_CARD_TRANSACTIONS
GROUP BY UNIDAD_NEGOCIO
ORDER BY UNIDAD_NEGOCIO;

SELECT
    ROLE_NAME,
    BUSINESS_UNIT
FROM SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING
ORDER BY ROLE_NAME, BUSINESS_UNIT;

-- -----------------------------------------------------------------------------
-- B. FR_BI_ANALYST — same queries, masked + RETAIL-only (zero app changes)
-- -----------------------------------------------------------------------------
USE ROLE FR_BI_ANALYST;
USE SECONDARY ROLES NONE;  -- isolate: only FR_BI_ANALYST is effective
USE WAREHOUSE WH_APP_MEDIUM;
USE DATABASE SUPERINTENDENCY_DEMO_DB;
USE SCHEMA CORE_BANKING_SCHEMA;

SELECT CURRENT_ROLE() AS ROL_ACTIVO, CURRENT_USER() AS USUARIO;

-- Same SQL as section A. PRESENTER: RUT is now ***-**-<12 hex> and the card
-- is fully masked; the shape of the result is otherwise identical.
SELECT
    RUT,
    NUMERO_TARJETA,
    CATEGORIA,
    MONTO,
    ESTADO,
    UNIDAD_NEGOCIO
FROM CREDIT_CARD_TRANSACTIONS
ORDER BY MONTO DESC
LIMIT 5;

-- RLS in action: only RETAIL survives (expected 15 969 793 rows; the admin
-- saw all three units / 50 000 000). Same table, same SQL, different rows.
SELECT
    UNIDAD_NEGOCIO,
    COUNT(*) AS TRANSACCIONES
FROM CREDIT_CARD_TRANSACTIONS
GROUP BY UNIDAD_NEGOCIO
ORDER BY UNIDAD_NEGOCIO;

-- Deterministic mask proof: filter by the pseudonym the analyst just saw —
-- rows must come back (> 0). A random mask would return 0 and break every
-- RUT-based filter in BI tools; this is why the mask hashes instead of
-- masking with a constant.
SELECT COUNT(*) AS FILAS_MISMO_TOKEN
FROM CREDIT_CARD_TRANSACTIONS
WHERE RUT = (SELECT MIN(RUT) FROM CREDIT_CARD_TRANSACTIONS);

-- Close the loop: back to admin, confirm identity flips back.
USE ROLE FR_DEMO_ADMIN;
USE SECONDARY ROLES NONE;
SELECT CURRENT_ROLE() AS ROL_ACTIVO_FINAL;
