-- =============================================================================
-- Session 4 - Integraciones y APIs (requisito C03 de la planilla)
-- 01_api_ingestion_procedure.sql
--
-- Objetivo: exponer al orquestador externo (Informatica IDMC) un hook nativo
-- de Snowflake para ingerir una API publica de tipos de cambio
-- (api.frankfurter.app: USD -> BRL/CLP/MXN) en la capa Bronze.
--
-- PREREQUISITO (IaC): correr `terraform apply` ANTES que este script - la
-- Network Rule y la External Access Integration (API_CURRENCY_INTEGRATION)
-- las provisiona Terraform (Demo/SB_Demo/terraform/main.tf + security.tf).
-- Sin la integracion, el CREATE PROCEDURE falla.
--
-- Rol de ejecucion: FR_DATA_ENGINEER (dueno de ingestas/cargas).
-- Script idempotente: la tabla usa IF NOT EXISTS y la procedure se reemplaza.
-- =============================================================================

USE SECONDARY ROLES NONE;
USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_INGESTION_MEDIUM;
USE DATABASE SUPERINTENDENCY_DEMO_DB;
USE SCHEMA STAGING_SCHEMA;

-- -----------------------------------------------------------------------------
-- 1. Tabla Bronze: payload crudo de la API (VARIANT, sin modelar)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS API_RAW_CURRENCY_DATA (
    INGESTION_TIME TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    RAW_PAYLOAD    VARIANT
);

-- -----------------------------------------------------------------------------
-- 2. Stored Procedure (Snowpark + requests) con External Access habilitado.
-- Los errores se propagan a proposito (sin try/except): el orquestador IDMC
-- debe ver el fallo de red/HTTP como un error de la llamada, no como exito.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_INGEST_EXTERNAL_API()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'requests')
EXTERNAL_ACCESS_INTEGRATIONS = ('API_CURRENCY_INTEGRATION')
HANDLER = 'main'
AS
$$
import requests
import snowflake.snowpark as snowpark


def main(session: snowpark.Session) -> str:
    url = "https://api.frankfurter.app/latest?from=USD&to=BRL,CLP,MXN"
    response = requests.get(url, timeout=10)
    response.raise_for_status()  # cualquier HTTP != 200 lanza excepcion

    # bindings en vez de concatenar: sin riesgo de inyeccion de comillas
    session.sql(
        """INSERT INTO SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.API_RAW_CURRENCY_DATA
               (RAW_PAYLOAD)
           SELECT PARSE_JSON(?)""",
        bindings=[response.text],
    ).collect()

    return f"Ingesta OK: {len(response.text)} bytes de api.frankfurter.app"
$$;

-- -----------------------------------------------------------------------------
-- 3. Verificacion local (evidencia) - la misma llamada que disparara el IDMC
-- -----------------------------------------------------------------------------
CALL SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.SP_INGEST_EXTERNAL_API();

SELECT INGESTION_TIME, RAW_PAYLOAD
FROM API_RAW_CURRENCY_DATA
ORDER BY INGESTION_TIME DESC
LIMIT 5;
