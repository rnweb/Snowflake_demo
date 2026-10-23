-- =============================================================================
-- Session 5 — 01: Performance deep-dive (Query Profile walkthrough)
-- =============================================================================
-- Role: FR_DATA_ENGINEER · Warehouse: WH_TRANSFORM_LARGE (LARGE) · 50 000 000
-- rows in SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.
--
-- How to present:
--   1. Run this file in a Snowsight worksheet as-is.
--   2. While (or right after) it runs, open the result header ->
--      "Query Profile" (or Activity -> Query History -> the query ->
--      Query Profile).
--   3. Narrate the profile top-down (see PRESENTER notes inline below).
--
-- PRESENTER — what to point at in the profile:
--   * Overview tab: "Total elapsed time" vs "Compilation time" — the plan
--     compiles in milliseconds; the seconds are pure execution on 50 M rows.
--   * "Bytes scanned" / "Partitions scanned": this query has NO date filter,
--     so a full scan of the table is expected — every partition is read.
--     The optional contrast query at the bottom adds a date predicate and
--     scans a fraction of the bytes: that is partition pruning in one click.
--   * Pipeline / steps tree: GROUP BY (aggregation) -> window functions
--     (LAG + 3-month moving average) -> QUALIFY (top-10 per month). Each
--     node shows its own time, rows in/out and memory — the classic
--     "scan once, transform in the pipeline, return few rows" story.
--   * COUNT(DISTINCT ID_TARJETA) forces a shuffle (distinct aggregation) —
--     visible as an extra stage; good hook to explain multi-statement
--     pipelines and why LARGE was chosen over XSMALL for dbt/BI workloads.
--   * No spill expected: if "Spilled" bytes are 0, say so — memory was
--     sufficient on the LARGE warehouse. If the presenter wants a spill
--     demo, re-run with a smaller warehouse and watch temp storage light up.
--
-- Expected: finishes in roughly 5–20 s on WH_TRANSFORM_LARGE; result is a
-- monthly top-10 ranking per business unit/category with MoM % change.
-- =============================================================================

USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_TRANSFORM_LARGE;
USE DATABASE SUPERINTENDENCY_DEMO_DB;
USE SCHEMA CORE_BANKING_SCHEMA;

-- -----------------------------------------------------------------------------
-- Main query — heavy analytic over the full mart
-- -----------------------------------------------------------------------------
-- PRESENTER: full scan (no predicate) + aggregation + two window frames +
-- QUALIFY top-N. Watch the profile: one table scan feeds every downstream
-- step; the result set is tiny (a few hundred rows) but the work is 50 M.
WITH mensual AS (
    SELECT
        DATE_TRUNC('MONTH', FECHA_TRANSACCION) AS MES,
        UNIDAD_NEGOCIO,
        CATEGORIA,
        COUNT(*)                        AS QTD_TRANSACCIONES,
        SUM(MONTO)                      AS MONTO_TOTAL,
        AVG(MONTO)                      AS MONTO_PROMEDIO,
        COUNT(DISTINCT ID_TARJETA)      AS TARJETAS_ACTIVAS
    FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
    GROUP BY 1, 2, 3
),
tendencia AS (
    SELECT
        MES,
        UNIDAD_NEGOCIO,
        CATEGORIA,
        QTD_TRANSACCIONES,
        MONTO_TOTAL,
        MONTO_PROMEDIO,
        TARJETAS_ACTIVAS,
        LAG(MONTO_TOTAL) OVER (
            PARTITION BY UNIDAD_NEGOCIO, CATEGORIA ORDER BY MES
        ) AS MONTO_MES_ANTERIOR,
        AVG(MONTO_TOTAL) OVER (
            PARTITION BY UNIDAD_NEGOCIO, CATEGORIA
            ORDER BY MES
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS MEDIA_MOVIL_3M
    FROM mensual
)
SELECT
    MES,
    UNIDAD_NEGOCIO,
    CATEGORIA,
    QTD_TRANSACCIONES,
    MONTO_TOTAL,
    ROUND(MONTO_PROMEDIO, 2)            AS MONTO_PROMEDIO,
    TARJETAS_ACTIVAS,
    ROUND(MONTO_MES_ANTERIOR, 2)        AS MONTO_MES_ANTERIOR,
    ROUND(
        100.0 * (MONTO_TOTAL - MONTO_MES_ANTERIOR)
        / NULLIF(MONTO_MES_ANTERIOR, 0), 2
    )                                   AS VAR_MOM_PCT,
    ROUND(MEDIA_MOVIL_3M, 2)            AS MEDIA_MOVIL_3M
FROM tendencia
WHERE MONTO_TOTAL > 100000000
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY MES ORDER BY MONTO_TOTAL DESC
) <= 10
ORDER BY MES DESC, MONTO_TOTAL DESC;

-- -----------------------------------------------------------------------------
-- Contrast query — same shape, one date predicate (partition pruning)
-- -----------------------------------------------------------------------------
-- PRESENTER: run this second and open its Query Profile next to the first
-- one. Same pipeline, but FECHA_TRANSACCION BETWEEN ... lets Snowflake prune
-- partitions: "Bytes scanned" drops sharply while the result stays useful
-- for a dashboard window. Talking point: "predicate push-down is free
-- performance — push the filter into SQL, not into the BI tool".
-- Expected: ~10x fewer bytes scanned; same seconds or faster.

WITH mensual AS (
    SELECT
        DATE_TRUNC('MONTH', FECHA_TRANSACCION) AS MES,
        UNIDAD_NEGOCIO,
        CATEGORIA,
        COUNT(*)                        AS QTD_TRANSACCIONES,
        SUM(MONTO)                      AS MONTO_TOTAL,
        AVG(MONTO)                      AS MONTO_PROMEDIO,
        COUNT(DISTINCT ID_TARJETA)      AS TARJETAS_ACTIVAS
    FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
    WHERE FECHA_TRANSACCION >= '2026-01-01'
      AND FECHA_TRANSACCION <  '2026-07-01'
    GROUP BY 1, 2, 3
),
tendencia AS (
    SELECT
        MES,
        UNIDAD_NEGOCIO,
        CATEGORIA,
        QTD_TRANSACCIONES,
        MONTO_TOTAL,
        MONTO_PROMEDIO,
        TARJETAS_ACTIVAS,
        LAG(MONTO_TOTAL) OVER (
            PARTITION BY UNIDAD_NEGOCIO, CATEGORIA ORDER BY MES
        ) AS MONTO_MES_ANTERIOR,
        AVG(MONTO_TOTAL) OVER (
            PARTITION BY UNIDAD_NEGOCIO, CATEGORIA
            ORDER BY MES
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS MEDIA_MOVIL_3M
    FROM mensual
)
SELECT
    MES,
    UNIDAD_NEGOCIO,
    CATEGORIA,
    QTD_TRANSACCIONES,
    MONTO_TOTAL,
    ROUND(MONTO_PROMEDIO, 2)            AS MONTO_PROMEDIO,
    TARJETAS_ACTIVAS,
    ROUND(MONTO_MES_ANTERIOR, 2)        AS MONTO_MES_ANTERIOR,
    ROUND(
        100.0 * (MONTO_TOTAL - MONTO_MES_ANTERIOR)
        / NULLIF(MONTO_MES_ANTERIOR, 0), 2
    )                                   AS VAR_MOM_PCT,
    ROUND(MEDIA_MOVIL_3M, 2)            AS MEDIA_MOVIL_3M
FROM tendencia
WHERE MONTO_TOTAL > 100000000
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY MES ORDER BY MONTO_TOTAL DESC
) <= 10
ORDER BY MES DESC, MONTO_TOTAL DESC;

-- -----------------------------------------------------------------------------
-- Optional — warehouse scaling check (talk-track for the closing slide)
-- -----------------------------------------------------------------------------
-- PRESENTER: if asked "why not XSMALL?" — show
--   SHOW WAREHOUSES LIKE 'WH_%';
-- sizes: WH_INGESTION_MEDIUM / WH_TRANSFORM_LARGE / WH_APP_MEDIUM.
-- The transform layer is LARGE because dbt builds and profile demos run
-- against 50 M rows; the app warehouse stays MEDIUM on purpose (trial-credit
-- guardrail). Auto-suspend keeps idle cost at zero between demos.
SHOW WAREHOUSES LIKE 'WH_%';
