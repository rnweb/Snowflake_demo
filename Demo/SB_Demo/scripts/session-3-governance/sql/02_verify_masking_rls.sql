-- =============================================================================
-- Session 3 — 02: Verify masking + row-level security (admin vs analyst)
-- =============================================================================
-- Start as FR_DEMO_ADMIN on WH_APP_XSMALL. The script switches roles mid-way,
-- so run the whole file in one worksheet / one session.
--
-- Expected results:
--   FR_DEMO_ADMIN  -> RUT y NUMERO_TARJETA en claro, 3 unidades, 18 000 filas
--   FR_BI_ANALYST  -> RUT '***-**-****', tarjeta '****-****-****-****',
--                     solo RETAIL (5 849 filas), misma SQL sin cambios de app
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A. FR_DEMO_ADMIN — plaintext PII, all business units
-- -----------------------------------------------------------------------------
SELECT RUT, NOMBRE, APELLIDO, ESTADO_CLIENTE
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
ORDER BY RUT
LIMIT 5;

SELECT NUMERO_TARJETA, CATEGORIA, MONTO, ESTADO, UNIDAD_NEGOCIO
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
ORDER BY MONTO DESC
LIMIT 5;

SELECT UNIDAD_NEGOCIO, COUNT(*) AS TRANSACCIONES
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
GROUP BY UNIDAD_NEGOCIO
ORDER BY UNIDAD_NEGOCIO;

SELECT ROLE_NAME, BUSINESS_UNIT
FROM SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING
ORDER BY ROLE_NAME, BUSINESS_UNIT;

-- -----------------------------------------------------------------------------
-- B. FR_BI_ANALYST — same queries, masked + RETAIL-only (zero app changes)
-- -----------------------------------------------------------------------------
USE ROLE FR_BI_ANALYST;
USE WAREHOUSE WH_APP_XSMALL;
USE DATABASE SUPERINTENDENCY_DEMO_DB;
USE SCHEMA CORE_BANKING_SCHEMA;

SELECT RUT, NOMBRE, APELLIDO, ESTADO_CLIENTE
FROM CLIENT_PROFILE_DIM
ORDER BY RUT
LIMIT 5;

SELECT NUMERO_TARJETA, CATEGORIA, MONTO, ESTADO, UNIDAD_NEGOCIO
FROM CREDIT_CARD_TRANSACTIONS
ORDER BY MONTO DESC
LIMIT 5;

SELECT UNIDAD_NEGOCIO, COUNT(*) AS TRANSACCIONES
FROM CREDIT_CARD_TRANSACTIONS
GROUP BY UNIDAD_NEGOCIO
ORDER BY UNIDAD_NEGOCIO;
