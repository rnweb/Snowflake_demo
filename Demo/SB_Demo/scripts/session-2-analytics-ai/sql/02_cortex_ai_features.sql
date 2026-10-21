-- =============================================================================
-- Session 2 — 02: Funciones de Inteligencia Artificial de Cortex (español)
-- =============================================================================
-- Rol: FR_DATA_ENGINEER | Almacén: WH_CORTEX_LARGE
--
-- Estas consultas demuestran las funciones de texto de Snowflake Cortex sobre
-- los datos de la demo bancaria (espacio de nombres moderno AI_*):
--
--   1. AI_SUMMARIZE  -> resumen ejecutivo de transacciones
--   2. AI_TRANSLATE -> traducción ES -> EN para reportes
--   3. AI_COMPLETE  -> veredicto de riesgo con contexto
--                      (patrón RAC sobre el mart, sin embeddings)
--   4. AI_COMPLETE  -> extracción estructurada (JSON)
--   5. RAG — vector store, embeddings (AI_EMBED) y búsqueda vetorial
--                      (VECTOR_INNER_PRODUCT + AI_COMPLETE / AI_EXTRACT)
--
-- NOTA (cuenta nueva / On-Demand): en cuentas creadas recientemente las
-- funciones heredadas SNOWFLAKE.CORTEX.* (SUMMARIZE, TRANSLATE, COMPLETE,
-- EMBED, EXTRACT_ANSWER) están bloqueadas con el error 399270
-- "New accounts are blocked from using legacy SNOWFLAKE.CORTEX functions".
-- Este script usa el espacio de nombres moderno AI_* (AI_SUMMARIZE,
-- AI_TRANSLATE, AI_COMPLETE, AI_EMBED, AI_EXTRACT), verificado extremo a
-- extremo en la cuenta On-Demand. El resto de la demo (datos, marts, RBAC,
-- modelo ML) no depende de estas consultas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Resumen ejecutivo de las transacciones de mayor monto
-- (AI_SUMMARIZE no admite agregados en línea — LISTAGG va en subconsulta)
-- -----------------------------------------------------------------------------
SELECT AI_SUMMARIZE(tx.transacciones) AS RESUMEN_EJECUTIVO
FROM (
    SELECT LISTAGG(
        'El ' || TO_VARCHAR(FECHA_TRANSACCION, 'YYYY-MM-DD HH24:MI')
        || ' se registro una transaccion de ' || TO_VARCHAR(MONTO)
        || ' pesos en ' || COMERCIO || ' (' || CIUDAD
        || '), categoria ' || CATEGORIA
        || ', estado ' || ESTADO
        || ', unidad de negocio ' || UNIDAD_NEGOCIO || '.',
        ' '
    ) WITHIN GROUP (ORDER BY MONTO DESC) AS transacciones
    FROM (
        SELECT FECHA_TRANSACCION, MONTO, COMERCIO, CIUDAD, CATEGORIA, ESTADO, UNIDAD_NEGOCIO
        FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
        WHERE MONTO >= 400000
        ORDER BY MONTO DESC
        LIMIT 30
    )
) tx;

-- -----------------------------------------------------------------------------
-- 2. Traducción al inglés del encabezado de un reporte de cumplimiento
-- -----------------------------------------------------------------------------
SELECT AI_TRANSLATE(
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
SELECT AI_COMPLETE(
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
SELECT AI_COMPLETE(
    'llama3.1-8b',
    'Extrae de este texto un JSON con las claves "unidad", "categoria" y '
    || '"monto_maximo", y nada mas. Texto: Unidad de negocio Retail con '
    || 'transacciones de hasta 480000 pesos en la categoria Electronica.'
) AS ALERTA_ESTRUCTURADA;

-- -----------------------------------------------------------------------------
-- 5. RAG - Preparación: schema y tabla de vectores (vector store)
-- -----------------------------------------------------------------------------
-- Bloque RAG: tipo VECTOR nativo, generación de embeddings con AI_EMBED y
-- funciones de búsqueda vetorial (VECTOR_INNER_PRODUCT + AI_COMPLETE/AI_EXTRACT).
-- Este bloque habilita un patrón RAG completo en la cuenta On-Demand.
--
-- El schema CORTEX_VECTOR_STORE es provisionado por Terraform (IaC), no por SQL.
-- Antes de ejecutar este bloque 5, debes correr `terraform apply` para crear el
-- schema y evitar el error 002043: "Schema does not exist".

-- Tabla para almacenar documentos/contexto + embedding (vector)
-- Usamos el tipo VECTOR nativo de Snowflake para embeddings.
CREATE OR REPLACE TABLE SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS (
    doc_id           STRING,
    title            STRING,
    content          STRING,
    metadata         VARIANT,
    embedding        VECTOR(FLOAT, 768),
    created_at       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- RAG - Inserción ejemplar de documentos (demo). Opcional en producción.
-- -----------------------------------------------------------------------------
-- En VALUES no se admiten funciones (PARSE_JSON) ni casts: se usa
-- INSERT ... SELECT ... FROM VALUES con alias de columnas.
INSERT INTO SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS (doc_id, title, content, metadata)
SELECT c1, c2, c3, PARSE_JSON(c4) FROM VALUES
  ('doc_001', 'Política de monitoreo Retail', 'La unidad Retail tiene reglas de revisión internas para transacciones mayores que establecen pasos de verificación y escalamiento.', '{"category":"risk_policy","unit":"Retail"}'),
  ('doc_002', 'Reporte trimestre Q2', 'Se detectaron transacciones atípicas en el último trimestre en la unidad Retail; se recomienda revisión manual de cuentas con actividad frecuente.', '{"category":"report","unit":"Retail"}'),
  ('doc_003', 'Guía AML', 'Patrones sospechosos incluyen compras fraccionadas, uso repetido de la misma tarjeta en comercios distintos y transferencias a cuentas de alto riesgo.', '{"category":"aml","unit":"Retail"}') AS t(c1, c2, c3, c4);

-- -----------------------------------------------------------------------------
-- RAG - Generación de embeddings y persistencia en la tabla (indexación)
-- -----------------------------------------------------------------------------
UPDATE SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS d
SET embedding = AI_EMBED('snowflake-arctic-embed-m-v1.5', d.content)
WHERE embedding IS NULL;

-- Verifica que embeddings se hayan generado
SELECT doc_id, title, created_at, CASE WHEN embedding IS NOT NULL THEN 'OK' ELSE 'MISSING' END AS emb_status
FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS;

-- -----------------------------------------------------------------------------
-- RAG - Búsqueda vectorial básica: similarity por producto interno (inner product)
-- -----------------------------------------------------------------------------
WITH query_embedding AS (
    SELECT AI_EMBED('snowflake-arctic-embed-m-v1.5',
        'Transacciones sospechosas por montos elevados en Retail durante el ultimo trimestre'
    ) AS q_emb
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
-- RAG - Recuperación + generación de respuesta con contexto (AI_COMPLETE)
-- -----------------------------------------------------------------------------
WITH query AS (
    SELECT 'Analiza el riesgo asociado a la siguiente consulta: transacciones por encima de 400000 en Retail' AS user_question
),
q_emb AS (
    SELECT AI_EMBED('snowflake-arctic-embed-m-v1.5', user_question) AS embedding
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
SELECT AI_COMPLETE(
    'llama3.1-70b',
    'Eres un analista de riesgos de la Superintendencia de Bancos. '
    || 'Usa el contexto recuperado para responder en español. Formato exacto: RIESGO: <ALTO|MEDIO|BAJO> - <justificacion corta>. Contexto: '
    || (SELECT context_text FROM context_concat)
) AS RAG_VEREDICTO;

-- -----------------------------------------------------------------------------
-- RAG - Alternativa: AI_EXTRACT en modo "question answering" para respuestas
-- más dirigidas (contexto recuperado + pregunta). Reemplaza al heredado
-- CORTEX.EXTRACT_ANSWER en cuentas nuevas (399270).
-- -----------------------------------------------------------------------------
WITH query AS (
    SELECT 'Analiza el riesgo asociado a la siguiente consulta: transacciones por encima de 400000 en Retail' AS user_question
),
q_emb AS (
    SELECT AI_EMBED('snowflake-arctic-embed-m-v1.5', user_question) AS embedding
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
-- (Las claves del objeto VARIANT de AI_EXTRACT son minúsculas: :response:question)
SELECT
    (
        AI_EXTRACT(
            (SELECT context_text FROM context_concat),
            PARSE_JSON('{"mode": "question answering", "question": "¿Qué unidad de negocio presenta transacciones atípicas y qué acción se recomienda?"}')
        )
    ):response:question AS EXTRACTED_ANSWER;

-- -----------------------------------------------------------------------------
-- RAG - Uso combinado: generar evidencia estructurada (JSON) y alimentar alertas
-- -----------------------------------------------------------------------------
WITH top1 AS (
    SELECT content
    FROM (
        SELECT d.content, VECTOR_INNER_PRODUCT(d.embedding,
            AI_EMBED('snowflake-arctic-embed-m-v1.5',
                'Buscar evidencia sobre transacciones de alto monto en Retail')
        ) AS score
        FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS d
        ORDER BY score DESC
        LIMIT 1
    )
)
SELECT AI_COMPLETE(
    'llama3.1-8b',
    'Extrae de este texto un JSON con las claves "unidad", "categoria" y "monto_maximo", y nada mas. Texto: '
    || (SELECT content FROM top1)
) AS ALERTA_ESTRUCTURADA_RAG;

-- -----------------------------------------------------------------------------
-- RAG - Notas de despliegue y consideraciones
-- -----------------------------------------------------------------------------
-- - Rol: FR_DATA_ENGINEER (usa WH_CORTEX_LARGE). Necesita USAGE on
--   SUPERINTENDENCY_DEMO_DB + build en CORTEX_VECTOR_STORE (grants via IaC).
-- - En cuentas nuevas usa SIEMPRE el espacio de nombres AI_* (AI_SUMMARIZE,
--   AI_TRANSLATE, AI_COMPLETE, AI_EMBED, AI_EXTRACT). Las funciones heredadas
--   SNOWFLAKE.CORTEX.* devuelven 399270 en cuentas creadas después de la
--   disponibilidad general de AI Functions.
-- - AI_EMBED('snowflake-arctic-embed-m-v1.5', ...) devuelve VECTOR(FLOAT, 768)
--   en esta cuenta; la columna del vector store debe usar esa misma dimensión.
-- - En la cláusula VALUES no se admiten funciones ni casts (error 002014):
--   usa INSERT ... SELECT ... FROM VALUES t(c1, c2, ...) con PARSE_JSON en el SELECT.
-- - Modelos verificados en esta cuenta: snowflake-arctic-embed-m-v1.5
--   (embeddings) y llama3.1-8b / llama3.1-70b (texto).
-- - Para producción: chunking de documentos, normalización, control de costos y
--   refresh incremental (solo embeddings para textos nuevos/actualizados).
-- =============================================================================

-- =============================================================================
-- FIN DEL ARCHIVO
-- =============================================================================
