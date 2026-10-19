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
--   5. RAG — vector store, embeddings y ejemplo de búsqueda vetorial
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

-- -----------------------------------------------------------------------------
-- 5. RAG - Preparación: schema y tabla de vectores (vector store)
-- -----------------------------------------------------------------------------
-- NUEVO BLOQUE (RAG): creación de Vector Type, generación de embeddings y
-- funciones de búsqueda vetorial (VECTOR_INNER_PRODUCT, CORTEX.EXTRACT_ANSWER)
-- Este bloque habilita un patrón RAG completo en la cuenta On‑Demand.

CREATE OR REPLACE SCHEMA IF NOT EXISTS SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE;

-- Tabla para almacenar documentos/contexto + embedding (vector)
-- Usamos el tipo VECTOR nativo de Snowflake para embeddings.
CREATE OR REPLACE TABLE SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS (
    doc_id           STRING,
    title            STRING,
    content          STRING,
    metadata         VARIANT,
    embedding        VECTOR,         -- VECTOR (dimensionalidad implícita / dinámica)
    created_at       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- RAG - Inserción ejemplar de documentos (demo). Opcional en producción.
-- -----------------------------------------------------------------------------
-- Inserta algunos documentos de demostración (ejemplo). En producción, deberías
-- llenar esta tabla con chunks del mart, políticas, logs, o extractos relevantes.
INSERT INTO SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS (doc_id, title, content, metadata)
VALUES
  ('doc_001', 'Política de monitoreo Retail', 'La unidad Retail tiene reglas de revisión internas para transacciones mayores que establecen pasos de verificación y escalamiento.', OBJECT_CONSTR[...] ),
  ('doc_002', 'Reporte trimestre Q2',            'Se detectaron transacciones atípicas en el último trimestre en la unidad Retail; se recomienda revisión manual de cuentas con actividad frecuen[...]', OBJECT_CONSTR[...] ),
  ('doc_003', 'Guía AML',                         'Patrones sospechosos incluyen compras fraccionadas, uso repetido de la misma tarjeta en comercios distintos y transferencias a cuentas de alto r[...]', OBJECT_CONSTR[...] );

-- -----------------------------------------------------------------------------
-- RAG - Generación de embeddings y persistencia en la tabla (indexación)
-- -----------------------------------------------------------------------------
-- Ajusta el nombre del modelo de embeddings si tu cuenta usa otro. Si la
-- función EMBED devuelve VARIANT/ARRAY en lugar de VECTOR, haz la conversión
-- necesaria (TO_VARIANT o CAST/TRY_CAST). Aquí usamos TRY_CAST por seguridad.
UPDATE SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS d
SET embedding = (
    TRY_CAST(
        SNOWFLAKE.CORTEX.EMBED('text-embedding-3-large', d.content)
        AS VECTOR
    )
)
WHERE embedding IS NULL;

-- Verifica que embeddings se hayan generado
SELECT doc_id, title, created_at, CASE WHEN embedding IS NOT NULL THEN 'OK' ELSE 'MISSING' END AS emb_status
FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS;

-- -----------------------------------------------------------------------------
-- RAG - Búsqueda vectorial básica: similarity por producto interno (inner product)
-- -----------------------------------------------------------------------------
-- Ejemplo de consulta: dado un query en texto, generar su embedding y buscar los
-- documentos más similares usando VECTOR_INNER_PRODUCT.
WITH query_embedding AS (
    SELECT TRY_CAST(SNOWFLAKE.CORTEX.EMBED('text-embedding-3-large',
        'Transacciones sospechosas por montos elevados en Retail durante el ultimo trimestre'
    ) AS VECTOR) AS q_emb
)
SELECT
    d.doc_id,
    d.title,
    d.metadata,
    VECTOR_INNER_PRODUCT(d.embedding, q.q_emb) AS score
FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS d
CROSS JOIN query_embedding q
WHERE d.embedding IS NOT NULL AND q.q_emb IS NOT NULL
ORDER BY score DESC
LIMIT 5;

-- -----------------------------------------------------------------------------
-- RAG - Recuperación + generación de respuesta con contexto (CORTEX.COMPLETE)
-- -----------------------------------------------------------------------------
-- Recuperamos los top-k documentos, concatenamos el contexto y pasamos a
-- CORTEX.COMPLETE para un veredicto en español.
WITH query AS (
    SELECT 'Analiza el riesgo asociado a la siguiente consulta: transacciones por encima de 400000 en Retail' AS user_question
),
q_emb AS (
    SELECT TRY_CAST(SNOWFLAKE.CORTEX.EMBED('text-embedding-3-large', user_question) AS VECTOR) AS embedding
    FROM query
),
retrieved AS (
    SELECT d.doc_id, d.title, d.content, d.metadata,
           VECTOR_INNER_PRODUCT(d.embedding, q_emb.embedding) AS score
    FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS d
    CROSS JOIN q_emb
    WHERE d.embedding IS NOT NULL
    ORDER BY score DESC
    LIMIT 5
),
context_concat AS (
    SELECT LISTAGG('[' || title || '] ' || content, '\n\n') WITHIN GROUP (ORDER BY score DESC) AS context_text
    FROM retrieved
)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-70b', -- modelo para generación. Ajusta si tu cuenta tiene otro modelo.
    'Eres un analista de riesgos de la Superintendencia de Bancos. '
    || 'Usa el contexto recuperado para responder en español. Formato exacto: RIESGO: <ALTO|MEDIO|BAJO> - <justificacion corta>. Contexto: '
    || (SELECT context_text FROM context_concat)
) AS RAG_VEREDICTO;

-- -----------------------------------------------------------------------------
-- RAG - Alternativa: usar CORTEX.EXTRACT_ANSWER (si disponible) para respuestas
-- más dirigidas (pregunta + context stack)
-- -----------------------------------------------------------------------------
-- Si tu cuenta expone SNOWFLAKE.CORTEX.EXTRACT_ANSWER, se puede usar directamente
-- pasando el contexto recuperado y la pregunta; ejemplo hipotético:
-- (Si la función no existe en tu cuenta, usa el paso anterior con COMPLETE)
SELECT
    SNOWFLAKE.CORTEX.EXTRACT_ANSWER(
        'llama3.1-70b',
        '¿Cuál es el veredicto de riesgo para transacciones > 400000 en Retail? Responde en español con formato: RIESGO: <ALTO|MEDIO|BAJO> - <1 línea>.',
        (SELECT context_text FROM context_concat)
    ) AS EXTRACTED_ANSWER;

-- -----------------------------------------------------------------------------
-- RAG - Uso combinado: generar evidencia estructurada (JSON) y alimentar alertas
-- -----------------------------------------------------------------------------
WITH top1 AS (
    SELECT content
    FROM (
        SELECT d.content, VECTOR_INNER_PRODUCT(d.embedding,
            TRY_CAST(SNOWFLAKE.CORTEX.EMBED('text-embedding-3-large',
                'Buscar evidencia sobre transacciones de alto monto en Retail') AS VECTOR)
        ) AS score
        FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS d
        ORDER BY score DESC
        LIMIT 1
    )
)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
    'llama3.1-8b',
    'Extrae de este texto un JSON con las claves "unidad", "categoria" y "monto_maximo", y nada mas. Texto: '
    || (SELECT content FROM top1)
) AS ALERTA_ESTRUCTURADA_RAG;

-- -----------------------------------------------------------------------------
-- RAG - Notas de despliegue y consideraciones
-- -----------------------------------------------------------------------------
-- - Asegúrate de que el role usado tenga permisos para ejecutar funciones CORTEX.*,
--   y para crear tablas/actualizar datos en SUPERINTENDENCY_DEMO_DB.
-- - Si la función EMBED o el tipo VECTOR devuelven otro formato (por ejemplo VARIANT),
--   ajusta el UPDATE para mapear/convertir: p.ej. embedding = TO_VARIANT(SNOWFLAKE.CORTEX.EMBED(...))
-- - Reemplaza nombres de modelo ('text-embedding-3-large', 'llama3.1-70b', etc.) por
--   los que estén disponibles en tu cuenta.
-- - Para producción: chunking de documentos, normalización, control de costos y
--   refresh incremental (solo embeddings para textos nuevos/actualizados).
-- -----------------------------------------------------------------------------

-- =============================================================================
-- FIN DEL ARCHIVO
-- =============================================================================
