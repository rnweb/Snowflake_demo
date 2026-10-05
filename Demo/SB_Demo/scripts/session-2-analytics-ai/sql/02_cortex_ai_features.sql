-- =============================================================================
-- Session 2 — 02: Funciones de Inteligencia Artificial de Cortex (español)
-- =============================================================================
-- Rol: FR_DATA_ENGINEER | Almacén: WH_CORTEX_LARGE
--
-- Estas consultas demuestran las funciones de texto de Snowflake Cortex sobre
-- los datos de la demo bancaria:
--
--   1. SNOWFLAKE.CORTEX.SUMMARIZE  -> resumen ejecutivo de transacciones
--   2. SNOWFLAKE.CORTEX.TRANSLATE  -> traducción ES -> EN para reportes
--   3. SNOWFLAKE.CORTEX.COMPLETE   -> veredicto de riesgo con contexto
--                                     (patrón RAC sobre el mart, sin embeddings)
--   4. SNOWFLAKE.CORTEX.COMPLETE   -> extracción estructurada (JSON)
--
-- IMPORTANTE: estas funciones requieren una cuenta que NO sea de prueba
-- (trial). En cuentas trial Snowflake devuelve el error 399258
-- "AI function ... is not available for trial accounts". El resto de la demo
-- (datos, marts, RBAC, modelo ML) no depende de estas consultas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Resumen ejecutivo de las transacciones de mayor monto
-- -----------------------------------------------------------------------------
SELECT SNOWFLAKE.CORTEX.SUMMARIZE(
    LISTAGG(
        'El ' || TO_VARCHAR(FECHA_TRANSACCION, 'YYYY-MM-DD HH24:MI')
        || ' se registro una transaccion de ' || TO_VARCHAR(MONTO)
        || ' pesos en ' || COMERCIO || ' (' || CIUDAD
        || '), categoria ' || CATEGORIA
        || ', estado ' || ESTADO
        || ', unidad de negocio ' || UNIDAD_NEGOCIO || '.',
        ' '
    ) WITHIN GROUP (ORDER BY MONTO DESC)
) AS RESUMEN_EJECUTIVO
FROM (
    SELECT FECHA_TRANSACCION, MONTO, COMERCIO, CIUDAD, CATEGORIA, ESTADO, UNIDAD_NEGOCIO
    FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
    WHERE MONTO >= 400000
    ORDER BY MONTO DESC
    LIMIT 30
);

-- -----------------------------------------------------------------------------
-- 2. Traducción al inglés del encabezado de un reporte de cumplimiento
-- -----------------------------------------------------------------------------
SELECT SNOWFLAKE.CORTEX.TRANSLATE(
    'La Superintendencia de Bancos requiere revision prioritaria de las '
    || 'transacciones por encima de 400000 pesos detectadas en la unidad de '
    || 'negocio Retail durante el ultimo trimestre.',
    'es',
    'en'
) AS TRADUCCION_INFORME;

-- -----------------------------------------------------------------------------
-- 3. Veredicto de riesgo en español con contexto de las 10 peores
--    transacciones (patrón RAC: contexto recuperado por SQL + LLM de Cortex)
-- -----------------------------------------------------------------------------
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-70b',
    'Eres un analista de riesgos de la Superintendencia de Bancos. '
    || 'Con base en el contexto de transacciones que sigue, responde en '
    || 'español con el formato exacto: RIESGO: <ALTO|MEDIO|BAJO> - '
    || '<justificacion de una linea>. Contexto: '
    || (
        SELECT LISTAGG(
            TO_VARCHAR(MONTO) || ' pesos, ' || COMERCIO || ', '
            || CATEGORIA || ', estado ' || ESTADO
            || ', unidad ' || UNIDAD_NEGOCIO,
            '; '
        ) WITHIN GROUP (ORDER BY MONTO DESC)
        FROM (
            SELECT MONTO, COMERCIO, CATEGORIA, ESTADO, UNIDAD_NEGOCIO
            FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
            ORDER BY MONTO DESC
            LIMIT 10
        )
    )
) AS VEREDICTO_RIESGO;

-- -----------------------------------------------------------------------------
-- 4. Extracción estructurada (JSON) para alimentar un sistema de alertas
-- -----------------------------------------------------------------------------
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-8b',
    'Extrae de este texto un JSON con las claves "unidad", "categoria" y '
    || '"monto_maximo", y nada mas. Texto: Unidad de negocio Retail con '
    || 'transacciones de hasta 480000 pesos en la categoria Electronica.'
) AS ALERTA_ESTRUCTURADA;
