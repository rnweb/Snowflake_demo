-- ============================================================================
-- Session 1 — 01: Raw tables (Spanish banking schema)
-- ============================================================================
-- Audience : Data Engineers / Architects — Superintendency of Banks
-- Layer    : SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA (raw landing zone)
-- Compute  : WH_INGESTION_XSMALL
-- Role     : FR_DATA_ENGINEER
--
-- Logical mapping from the official Snowflake Quickstarts:
--   CUSTOMERS   -> CLIENTES          (SSN      -> RUT)
--   CREDIT_CARDS-> TARJETAS_CREDITO  (CARD_NUMBER -> NUMERO_TARJETA)
--   TRANSACTIONS-> TRANSACCIONES
--
-- Executed automatically by python/generate_and_load.py. Can also be run
-- in a Snowflake worksheet (the CSVs still require the Python loader for
-- PUT, which is not available from worksheets).
-- ============================================================================

CREATE TABLE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.CLIENTES (
    RUT               VARCHAR(20)  NOT NULL,  -- national ID (Rol Unico Tributario)
    NOMBRE            VARCHAR(60)  NOT NULL,
    APELLIDO          VARCHAR(60)  NOT NULL,
    FECHA_NACIMIENTO  DATE         NOT NULL,
    SEXO              VARCHAR(1),
    EMAIL             VARCHAR(120),
    TELEFONO          VARCHAR(20),
    CIUDAD            VARCHAR(60),
    REGION            VARCHAR(60),
    ESTADO            VARCHAR(20)  NOT NULL,  -- ACTIVO | SUSPENDIDO | BLOQUEADO
    FECHA_ALTA        DATE         NOT NULL,
    CARGADO_EN        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TARJETAS_CREDITO (
    ID_TARJETA         VARCHAR(20)   NOT NULL,
    RUT                VARCHAR(20)   NOT NULL,
    NUMERO_TARJETA     VARCHAR(25)   NOT NULL,  -- PAN (masked at query time in Session 3)
    TIPO               VARCHAR(20)   NOT NULL,  -- ESTANDAR | ORO | PLATINO
    LIMITE_CREDITO     NUMBER(14,2),
    FECHA_EMISION      DATE,
    FECHA_VENCIMIENTO  DATE,
    ESTADO             VARCHAR(20),             -- ACTIVA | BLOQUEADA | VENCIDA
    UNIDAD_NEGOCIO     VARCHAR(20),             -- CORPORATIVO | RETAIL | PYME
    CARGADO_EN         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES (
    ID_TRANSACCION     VARCHAR(25)   NOT NULL,
    ID_TARJETA         VARCHAR(20)   NOT NULL,
    RUT                VARCHAR(20)   NOT NULL,
    FECHA_TRANSACCION  TIMESTAMP_NTZ NOT NULL,
    MONTO              NUMBER(14,2)  NOT NULL,  -- CLP
    CATEGORIA          VARCHAR(40),
    COMERCIO           VARCHAR(80),
    CIUDAD             VARCHAR(60),
    ESTADO             VARCHAR(20)   NOT NULL,  -- APROBADA | RECHAZADA | PENDIENTE
    UNIDAD_NEGOCIO     VARCHAR(20),             -- drives row-level security (Session 3)
    CARGADO_EN         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE FILE FORMAT SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.RAW_CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL');

CREATE STAGE IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.RAW_STAGE;
