-- ============================================================================
-- Session 1 — 04: 50M-row generator for TRANSACCIONES (PG-06 data-volume demo)
-- ============================================================================
-- Audience : Data Engineers / Architects — Superintendency of Banks
-- Layer    : SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA (raw landing zone)
-- Compute  : WH_INGESTION_XSMALL
-- Role     : FR_DATA_ENGINEER
--
-- Generates 50 000 000 synthetic transactions in-Snowflake (TABLE(GENERATOR))
-- with real referential integrity: ID_TARJETA is drawn from the actual
-- ACTIVE cards in TARJETAS_CREDITO and RUT / UNIDAD_NEGOCIO come from that
-- same card (so the dbt relationship test RUT -> client_profile_dim and the
-- RLS unit distribution stay coherent). Domain values (categories, merchants,
-- cities, 85/10/5 estado split, CLP amount range) mirror the Session 1
-- Python loader so downstream dbt accepted_values tests keep passing.
--
-- Usage (as FR_DATA_ENGINEER on WH_INGESTION_XSMALL):
--   1. Run this file, then SWAP + DROP the legacy 18k table (statements below).
--   2. Run `dbt build --full-refresh` (the gold model is incremental — a
--      plain build would only pick rows newer than the old max timestamp).
--   3. Re-apply Terraform if dbt's CREATE OR REPLACE dropped column masking
--      policy attachments on the gold marts.
-- ============================================================================

-- Staging copy for the swap (idempotent; truncated by CREATE OR REPLACE below
-- only when re-run — a re-run recreates it empty before the INSERT).
CREATE OR REPLACE TABLE SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES_50M
    LIKE SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES;

INSERT INTO SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES_50M (
    ID_TRANSACCION, ID_TARJETA, RUT, FECHA_TRANSACCION, MONTO,
    CATEGORIA, COMERCIO, CIUDAD, ESTADO, UNIDAD_NEGOCIO
)
SELECT
    'TX-' || LPAD(TO_VARCHAR(n + 1), 8, '0')                        AS ID_TRANSACCION,
    IDS[IDX]::VARCHAR                                                AS ID_TARJETA,
    RUTS[IDX]::VARCHAR                                               AS RUT,
    TIMESTAMPADD(SECOND, UNIFORM(0, 31535999, RANDOM()),
                 '2025-10-01 00:00:00'::TIMESTAMP_NTZ)              AS FECHA_TRANSACCION,
    ROUND(UNIFORM(1500, 500000, RANDOM()), 2)                       AS MONTO,
    ARRAY_CONSTRUCT('SUPERMERCADO', 'RESTAURANTE', 'FARMACIA', 'BENCINA', 'ROPA', 'VIAJES', 'ELECTRONICA', 'EDUCACION', 'SALUD', 'ENTRETENIMIENTO')[FLOOR(UNIFORM(0, 9, RANDOM()))::INT]::VARCHAR  AS CATEGORIA,
    ARRAY_CONSTRUCT('Jumbo', 'Lider', 'Santa Isabel', 'Mercadona', 'Rappi', 'Uber', 'Cencosud', 'Falabella', 'Paris', 'Redbanc', 'Cruz Verde', 'Salcobrand', 'ENAP', 'CinemaColombus', 'Libreria Nacional', 'Paris Cencosud', 'Zara', 'H&M')[FLOOR(UNIFORM(0, 17, RANDOM()))::INT]::VARCHAR  AS COMERCIO,
    ARRAY_CONSTRUCT('Santiago', 'Valparaiso', 'Concepcion', 'La Serena', 'Antofagasta', 'Vina del Mar', 'Temuco', 'Rancagua', 'Puerto Montt', 'Chillan')[FLOOR(UNIFORM(0, 9, RANDOM()))::INT]::VARCHAR  AS CIUDAD,
    CASE WHEN U_ESTADO <= 85 THEN 'APROBADA'
         WHEN U_ESTADO <= 95 THEN 'RECHAZADA'
         ELSE 'PENDIENTE' END                                        AS ESTADO,
    UNITS[IDX]::VARCHAR                                              AS UNIDAD_NEGOCIO
FROM (
    SELECT
        seq4()                                                       AS n,
        (UNIFORM(0, 5999, RANDOM()) % c.N)::INT                      AS IDX,
        UNIFORM(1, 100, RANDOM())                                    AS U_ESTADO,
        c.IDS, c.RUTS, c.UNITS
    FROM TABLE(GENERATOR(ROWCOUNT => 50000000)) g
    CROSS JOIN (
        SELECT
            ARRAY_AGG(ID_TARJETA)     AS IDS,
            ARRAY_AGG(RUT)            AS RUTS,
            ARRAY_AGG(UNIDAD_NEGOCIO) AS UNITS,
            COUNT(*)                  AS N
        FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TARJETAS_CREDITO
        WHERE ESTADO = 'ACTIVA'
    ) c
);

-- Swap the 50M table into the active raw table name, then drop the legacy
-- 18k dataset (now parked under the _50M name). dbt reads TRANSACCIONES.
ALTER TABLE SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES
    SWAP WITH SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES_50M;

DROP TABLE IF EXISTS SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES_50M;

-- Expected: STAGING_SCHEMA.TRANSACCIONES = 50 000 000 rows.
