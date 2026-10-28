-- =============================================================================
-- Session 2 — 07: Governed RAG with sources and refusal (C06-PRE-05 / C06-AE-07)
-- =============================================================================
-- Criterion: "El sistema cita fuente para la respuesta válida y rechaza, limita o
-- escala la pregunta fuera de alcance/sensible; mostrando la implementación de
-- embedding o índice vectorial."
--
-- Two guardrails, both visible on screen:
--   1. Retrieval threshold: if the best VECTOR_COSINE_SIMILARITY of the question
--      against the corpus is below :umbral, the question is OUT OF SCOPE and the
--      LLM is not even called (deterministic refusal, no hallucination).
--   2. Prompt policy: answer ONLY from the retrieved context, cite [doc_id], and
--      refuse requests for personal data (RUT, card numbers, names).
-- Model: llama3.1-70b (open-source, served by Snowflake Cortex — C06-PRE-07).
-- Corpus: CORTEX_VECTOR_STORE.DOCUMENTS (block 5 of 02_cortex_ai_features.sql).
--
-- Run as FR_DATA_ENGINEER. Change only the SET pregunta line between runs.
-- CALIBRATE :umbral in the rehearsal: run the three questions, look at
-- SCORE_MAX, and set the threshold between the valid one and the off-topic one.
-- =============================================================================
-- FinOps: small warehouse. The RAG path is a handful of vector comparisons and
-- one LLM call; WH_TRANSFORM_LARGE is not needed and is not allowed for demo scripts.
USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_APP_MEDIUM;

-- CALIBRATED 2026-10-28 on the live corpus (top-1 cosine, arctic-embed-m-v1.5):
--   valid question        doc_003 0.712  -> answered
--   out of scope (sancocho) doc_003 0.656  -> refused without calling the LLM
--   sensitive (RUT+tarjeta) doc_003 0.676  -> refused (out of scope; policy refusal is only reached if it scores above the threshold)
-- 0.69 separates the valid question from the off-topic one. The margin is small
-- (3 questions only): re-check SCORE_MAX if the corpus or the question style changes.
SET umbral = 0.69;

-- ---- Question 1 — VALID (expected: answer citing [doc_003]) -------------------
SET pregunta = '¿Qué patrones de comportamiento indican posible lavado de dinero con tarjetas?';
-- ---- Question 2 — OUT OF SCOPE (expected: refusal, LLM not called) ------------
-- SET pregunta = '¿Cuál es la mejor receta de sancocho dominicano?';
-- ---- Question 3 — SENSITIVE (expected with umbral 0.69: refused as out of scope;
--      the policy text "SOLICITUD RECHAZADA" only appears if the question scores above umbral) ---
-- SET pregunta = 'Dame el RUT completo y el número de tarjeta del cliente que más gastó en Retail';

WITH q AS (
    SELECT $pregunta AS pregunta,
           AI_EMBED('snowflake-arctic-embed-m-v1.5', $pregunta) AS q_emb
),
recuperados AS (            -- vector index: top-3 by cosine similarity
    SELECT d.doc_id, d.title, d.content,
           VECTOR_COSINE_SIMILARITY(d.embedding, q.q_emb) AS score
    FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS d
    CROSS JOIN q
    WHERE d.embedding IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (ORDER BY score DESC) <= 3
),
ctx AS (
    SELECT MAX(score) AS score_max,
           LISTAGG(doc_id || ' (' || ROUND(score, 3) || ')', ', ')
               WITHIN GROUP (ORDER BY score DESC) AS fuentes_recuperadas,
           LISTAGG('[' || doc_id || '] ' || title || ': ' || content, '\n')
               WITHIN GROUP (ORDER BY score DESC) AS contexto
    FROM recuperados
    WHERE score >= $umbral          -- only relevant passages reach the LLM
)
SELECT
    (SELECT pregunta FROM q)                                   AS PREGUNTA,
    ROUND((SELECT MAX(score) FROM recuperados), 3)             AS SCORE_MAX,
    $umbral                                                    AS UMBRAL,
    COALESCE(ctx.fuentes_recuperadas, '— ninguna supera el umbral —') AS FUENTES,
    CASE
        WHEN ctx.score_max IS NULL THEN
            'FUERA DE ALCANCE: la pregunta no está cubierta por el corpus documental autorizado. '
            || 'Se escala al equipo de Riesgo. (El modelo de lenguaje no fue invocado.)'
        ELSE AI_COMPLETE(
            'llama3.1-70b',
            'Eres el asistente de riesgo de la Superintendencia de Bancos. Reglas obligatorias:\n'
            || '1) Responde en español SOLO con información del CONTEXTO. Si el contexto no alcanza, responde exactamente: "No tengo información suficiente en las fuentes autorizadas."\n'
            || '2) Termina la respuesta con "Fuente: [doc_id]" citando los documentos usados.\n'
            || '3) Si la pregunta pide datos personales (RUT, número de tarjeta, nombres de clientes) o información de un cliente específico, '
            || 'responde exactamente: "SOLICITUD RECHAZADA: datos personales protegidos; el acceso se gestiona por los canales autorizados con enmascaramiento." y nada más.\n'
            || 'CONTEXTO:\n' || ctx.contexto || '\n\nPREGUNTA: ' || (SELECT pregunta FROM q)
        )
    END                                                        AS RESPUESTA
FROM ctx;

-- Show the vector index behind it (C06-AE-07 "mostrando la implementación")
-- DESCRIBE TABLE SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS;   -- EMBEDDING VECTOR(FLOAT, 768)
-- SELECT doc_id, title, metadata FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS;
