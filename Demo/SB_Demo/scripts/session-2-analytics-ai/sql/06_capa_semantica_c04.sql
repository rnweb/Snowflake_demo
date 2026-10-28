-- =============================================================================
-- Session 2 — 06: Governed semantic layer for Power BI (C04)
-- =============================================================================
-- C04-PRE-06  governed semantic layer: business names, relationships,
--             descriptions and comments for every field
-- C04-PRE-04  one metric with two conflicting definitions (Ticket Promedio)
--             to show duplicate-metric control
-- C04-AE-04   Power BI picks up business names (via the consumption view)
-- C04-AE-06   the official metric is defined once and reused by any consumer
--
-- Two objects, both on top of the governed mart (masking + RLS keep applying,
-- because the policies live on the base tables and are evaluated for the
-- role that queries):
--   1. VW_TRANSACCIONES_NEGOCIO  consumption view with business names and a
--                                comment on every column (Power BI imports it)
--   2. SV_RIESGO_TARJETAS        native SEMANTIC VIEW: tables, relationship,
--                                dimensions, facts and the OFFICIAL metrics
--                                (single source of truth; also serves
--                                Cortex Analyst / natural-language questions)
--
-- Run: block 0 as ACCOUNTADMIN (or FR_DEMO_ADMIN if it holds the grant
-- privileges), the rest as FR_DATA_ENGINEER. Idempotent.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Privileges (ACCOUNTADMIN)
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
GRANT CREATE VIEW, CREATE SEMANTIC VIEW
  ON SCHEMA SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA TO ROLE FR_DATA_ENGINEER;

USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_APP_MEDIUM;
USE SCHEMA SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA;

-- -----------------------------------------------------------------------------
-- 1. Consumption view with business names (what Power BI shows to the user)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_TRANSACCIONES_NEGOCIO (
    "Id Transacción"     COMMENT 'Identificador único de la transacción.',
    "RUT Cliente"        COMMENT 'Identificación nacional del cliente. Enmascarada (seudónimo determinístico) para roles no autorizados.',
    "Número de Tarjeta"  COMMENT 'Número de la tarjeta de crédito. Enmascarado para roles no autorizados.',
    "Fecha"              COMMENT 'Fecha y hora de la transacción.',
    "Monto"              COMMENT 'Monto de la transacción en moneda local.',
    "Categoría"          COMMENT 'Rubro del comercio (Supermercado, Viajes, Electrónica, etc.).',
    "Comercio"           COMMENT 'Nombre del comercio.',
    "Ciudad"             COMMENT 'Ciudad donde se realizó la transacción.',
    "Estado"             COMMENT 'Aprobada, Rechazada o Pendiente.',
    "Unidad de Negocio"  COMMENT 'Corporativo, Retail o Pyme. Atributo de seguridad por fila (RLS).',
    "Región Cliente"     COMMENT 'Región de residencia del cliente.',
    "Estado Cliente"     COMMENT 'Activo, Suspendido o Bloqueado.'
)
COMMENT = 'C04: vista de consumo con nombres de negocio sobre el mart gobernado. Enmascaramiento y RLS se heredan de las tablas base.'
AS
SELECT t.ID_TRANSACCION,
       t.RUT,
       t.NUMERO_TARJETA,
       t.FECHA_TRANSACCION,
       t.MONTO,
       t.CATEGORIA,
       t.COMERCIO,
       t.CIUDAD,
       t.ESTADO,
       t.UNIDAD_NEGOCIO,
       c.REGION,
       c.ESTADO_CLIENTE
FROM CREDIT_CARD_TRANSACTIONS t
LEFT JOIN CLIENT_PROFILE_DIM c ON c.RUT = t.RUT;

-- -----------------------------------------------------------------------------
-- 2. Native semantic view: the OFFICIAL metric definitions live here, once
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW SV_RIESGO_TARJETAS
  TABLES (
    trx AS SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
      PRIMARY KEY (ID_TRANSACCION)
      WITH SYNONYMS = ('transacciones', 'operaciones con tarjeta')
      COMMENT = 'Hechos: transacciones de tarjeta de crédito (50 M, sintéticas).',
    cli AS SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM
      PRIMARY KEY (RUT)
      WITH SYNONYMS = ('clientes', 'tarjetahabientes')
      COMMENT = 'Dimensión de clientes.'
  )
  RELATIONSHIPS (
    trx_a_cliente AS trx (RUT) REFERENCES cli
  )
  FACTS (
    trx.monto AS MONTO COMMENT = 'Monto de la transacción en moneda local.'
  )
  DIMENSIONS (
    trx.fecha            AS FECHA_TRANSACCION COMMENT = 'Fecha y hora de la transacción.',
    trx.mes              AS DATE_TRUNC('MONTH', FECHA_TRANSACCION) COMMENT = 'Mes de la transacción.',
    trx.unidad_negocio   AS UNIDAD_NEGOCIO WITH SYNONYMS = ('segmento', 'banca')
                         COMMENT = 'Corporativo, Retail o Pyme (atributo de RLS).',
    trx.categoria        AS CATEGORIA WITH SYNONYMS = ('rubro')
                         COMMENT = 'Rubro del comercio.',
    trx.estado           AS ESTADO COMMENT = 'Aprobada, Rechazada o Pendiente.',
    trx.ciudad           AS CIUDAD COMMENT = 'Ciudad de la transacción.',
    cli.region           AS REGION COMMENT = 'Región de residencia del cliente.',
    cli.estado_cliente   AS ESTADO_CLIENTE COMMENT = 'Activo, Suspendido o Bloqueado.'
  )
  METRICS (
    trx.total_transacciones AS COUNT(trx.ID_TRANSACCION)
      COMMENT = 'Número de transacciones (todos los estados).',
    trx.monto_aprobado AS SUM(CASE WHEN trx.ESTADO = 'APROBADA' THEN trx.MONTO END)
      COMMENT = 'Suma del monto de las transacciones APROBADAS.',
    trx.ticket_promedio AS
      SUM(CASE WHEN trx.ESTADO = 'APROBADA' THEN trx.MONTO END)
      / NULLIF(COUNT(CASE WHEN trx.ESTADO = 'APROBADA' THEN 1 END), 0)
      WITH SYNONYMS = ('ticket medio', 'gasto promedio')
      COMMENT = 'DEFINICIÓN OFICIAL: monto promedio de las transacciones APROBADAS. Rechazadas y pendientes no son consumo efectivo y quedan fuera.',
    trx.pct_rechazo AS
      COUNT(CASE WHEN trx.ESTADO = 'RECHAZADA' THEN 1 END) * 100.0
      / NULLIF(COUNT(trx.ID_TRANSACCION), 0)
      COMMENT = 'Porcentaje de transacciones rechazadas sobre el total.',
    cli.clientes_unicos AS COUNT(DISTINCT cli.RUT)
      COMMENT = 'Clientes distintos (cuenta sobre el RUT, también enmascarado).'
  )
  COMMENT = 'C04: capa semántica gobernada — definiciones oficiales de indicadores de riesgo de tarjetas.';

-- -----------------------------------------------------------------------------
-- 3. Grants for the consumer persona (Power BI uses DEMO_ANALYST / FR_BI_ANALYST)
-- -----------------------------------------------------------------------------
GRANT SELECT ON VIEW VW_TRANSACCIONES_NEGOCIO TO ROLE FR_BI_ANALYST;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SV_RIESGO_TARJETAS TO ROLE FR_BI_ANALYST;

-- -----------------------------------------------------------------------------
-- 4. DEMO — the semantic layer is visible and documented (C04-PRE-06)
-- -----------------------------------------------------------------------------
DESCRIBE SEMANTIC VIEW SV_RIESGO_TARJETAS;      -- tables, relationship, dims, metrics + comments

-- Official metrics by business unit, straight from the semantic view
SELECT * FROM SEMANTIC_VIEW(
    SV_RIESGO_TARJETAS
    DIMENSIONS trx.unidad_negocio
    METRICS trx.total_transacciones, trx.ticket_promedio, trx.pct_rechazo
) ORDER BY unidad_negocio;

-- -----------------------------------------------------------------------------
-- 5. DEMO — two conflicting definitions of the same metric (C04-PRE-04)
-- -----------------------------------------------------------------------------
-- Two areas, the same label "Ticket Promedio", two different meanings:
--   Riesgo (OFFICIAL, semantic view): average amount per APPROVED transaction
--   Comercial (improvised in a report): approved spend per CLIENT
-- Note: averaging all states vs approved only is NOT a usable contrast here —
-- the synthetic generator draws MONTO independently of ESTADO, so both averages
-- differ by cents (verified 27/10: -13.68 / +6.36 / -0.04 on ~250k).
USE ROLE FR_DATA_ENGINEER;      -- sees the three units
WITH improvisada AS (   -- "Ticket Promedio" del área Comercial: gasto por cliente
    SELECT UNIDAD_NEGOCIO,
           ROUND(SUM(CASE WHEN ESTADO = 'APROBADA' THEN MONTO END)
                 / COUNT(DISTINCT RUT), 2) AS TICKET_PROMEDIO_COMERCIAL
    FROM CREDIT_CARD_TRANSACTIONS
    GROUP BY 1
),
oficial AS (            -- definición oficial (capa semántica): por transacción aprobada
    SELECT unidad_negocio AS UNIDAD_NEGOCIO, ROUND(ticket_promedio, 2) AS TICKET_PROMEDIO_OFICIAL
    FROM SEMANTIC_VIEW(SV_RIESGO_TARJETAS DIMENSIONS trx.unidad_negocio METRICS trx.ticket_promedio)
)
SELECT i.UNIDAD_NEGOCIO,
       i.TICKET_PROMEDIO_COMERCIAL,
       o.TICKET_PROMEDIO_OFICIAL,
       ROUND(i.TICKET_PROMEDIO_COMERCIAL / o.TICKET_PROMEDIO_OFICIAL, 1) AS VECES_MAYOR
FROM improvisada i JOIN oficial o USING (UNIDAD_NEGOCIO)
ORDER BY 1;
-- Verified 27/10 on the new account: official ~250 760 for every unit; the
-- "Comercial" figure is ~72 000-75 600 times larger (600 synthetic clients
-- concentrate 50 M transactions). Same name, incompatible numbers: this is the
-- duplicate the semantic layer prevents. The official one is the metric
-- certified in Power BI (DAX "Ticket Promedio" = same formula).

-- -----------------------------------------------------------------------------
-- 6. DEMO — governance is inherited (run as the analyst)
-- -----------------------------------------------------------------------------
-- USE ROLE FR_BI_ANALYST;
-- SELECT * FROM SEMANTIC_VIEW(SV_RIESGO_TARJETAS DIMENSIONS trx.unidad_negocio METRICS trx.total_transacciones);
--   expected: only RETAIL (RLS), 15 969 793
-- SELECT "RUT Cliente", "Número de Tarjeta", "Unidad de Negocio" FROM VW_TRANSACCIONES_NEGOCIO LIMIT 5;
--   expected: RUT ***-**-<hash>, card ****-****-****-****, only RETAIL
