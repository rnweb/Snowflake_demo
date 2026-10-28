-- =============================================================================
-- Session 2 — 05: Data drift detection for DETECTOR_FRAUDES (C06-AE-06)
-- =============================================================================
-- Metric: PSI (Population Stability Index) per model feature, baseline (training
-- distribution) vs current scoring batch.  PSI < 0.10 stable | 0.10–0.25 watch |
-- > 0.25 drift.  A native Snowflake ALERT records an incident when PSI > 0.25.
-- Features: MONTO (deciles of the baseline) and HORA (24 buckets), the same
-- features used by session-2/python/01_train_fraud_model.py.
-- Run as FR_DATA_ENGINEER (sees all units; PII is never read here).
--
-- WAREHOUSE: WH_AUDIT_SMALL (X-Small, auto-suspend 60 s). The drift check reads
-- only two small tables and a view; it does not need a large warehouse. The
-- one-time SAMPLE(1) builds scan the 50M mart once and are the slowest step.
--
-- DEMO FLOW (run top to bottom):
--   Setup (sections 0-3) -> simulate drift (section 4) -> STOP THE ALERT (section 5).
--   Section 5 is part of the demo, not optional cleanup: the alert is scheduled
--   and would keep running (and consuming credits) after the presentation.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Grants (ACCOUNTADMIN, one time). Also codified in terraform/security.tf
--    (engineer_wh_audit), so Terraform and the account stay aligned.
-- -----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE FR_DATA_ENGINEER;
GRANT CREATE ALERT, CREATE TABLE, CREATE VIEW ON SCHEMA SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA TO ROLE FR_DATA_ENGINEER;
GRANT USAGE ON WAREHOUSE WH_AUDIT_SMALL TO ROLE FR_DATA_ENGINEER;

USE ROLE FR_DATA_ENGINEER;
USE WAREHOUSE WH_AUDIT_SMALL;
USE SCHEMA SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA;

-- -----------------------------------------------------------------------------
-- 1. Baseline = training distribution (1 % sample of the 50M mart, ~500k rows)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DRIFT_BASELINE AS
SELECT MONTO, HOUR(FECHA_TRANSACCION) AS HORA, DAYOFWEEK(FECHA_TRANSACCION) AS DIA_SEMANA
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS SAMPLE (1);

CREATE TABLE IF NOT EXISTS MODEL_DRIFT_METRICS (
    MEDIDO_EN TIMESTAMP_NTZ, LOTE VARCHAR, FEATURE VARCHAR, PSI FLOAT, NIVEL VARCHAR
) COMMENT = 'C06-AE-06: histórico de PSI por feature y lote.';
CREATE TABLE IF NOT EXISTS MODEL_DRIFT_ALERTS (
    DETECTADO_EN TIMESTAMP_NTZ, LOTE VARCHAR, FEATURE VARCHAR, PSI FLOAT, MENSAJE VARCHAR
) COMMENT = 'C06-AE-06: incidentes registrados por la alerta ALRT_DRIFT_DETECTOR_FRAUDES.';

-- -----------------------------------------------------------------------------
-- 2. PSI view: always compares DRIFT_BASELINE with the current batch DRIFT_LOTE_ACTUAL
-- -----------------------------------------------------------------------------
-- Batch 1: a normal batch (another sample, same distribution) -> expect STABLE
CREATE OR REPLACE TABLE DRIFT_LOTE_ACTUAL AS
SELECT 'LOTE_NORMAL' AS LOTE, MONTO, HOUR(FECHA_TRANSACCION) AS HORA, DAYOFWEEK(FECHA_TRANSACCION) AS DIA_SEMANA
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS SAMPLE (1);

CREATE OR REPLACE VIEW VW_DRIFT_PSI
  COMMENT = 'C06-AE-06: PSI por feature (baseline vs lote actual).'
AS
WITH EDGES AS (              -- decile bounds of MONTO in the baseline
    SELECT B, LAG(HI) OVER (ORDER BY B) AS LO_EXCL, IFF(B = 10, NULL, HI) AS HI_INCL
    FROM (SELECT B, MAX(MONTO) AS HI
          FROM (SELECT MONTO, NTILE(10) OVER (ORDER BY MONTO) AS B FROM DRIFT_BASELINE)
          GROUP BY B)
),
MONTO_B AS (
    SELECT 'BASE' AS LADO, e.B FROM DRIFT_BASELINE x JOIN EDGES e
      ON (e.LO_EXCL IS NULL OR x.MONTO > e.LO_EXCL) AND (e.HI_INCL IS NULL OR x.MONTO <= e.HI_INCL)
    UNION ALL
    SELECT 'ACTUAL', e.B FROM DRIFT_LOTE_ACTUAL x JOIN EDGES e
      ON (e.LO_EXCL IS NULL OR x.MONTO > e.LO_EXCL) AND (e.HI_INCL IS NULL OR x.MONTO <= e.HI_INCL)
),
HORA_B AS (
    SELECT 'BASE' AS LADO, HORA AS B FROM DRIFT_BASELINE
    UNION ALL SELECT 'ACTUAL', HORA FROM DRIFT_LOTE_ACTUAL
),
DIST AS (
    SELECT 'MONTO' AS FEATURE, LADO, B, COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY LADO) AS P FROM MONTO_B GROUP BY LADO, B
    UNION ALL
    SELECT 'HORA', LADO, B, COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY LADO) FROM HORA_B GROUP BY LADO, B
),
PIV AS (
    SELECT FEATURE, B,
           GREATEST(COALESCE(MAX(IFF(LADO = 'BASE', P, NULL)), 0), 0.0001)   AS P_BASE,
           GREATEST(COALESCE(MAX(IFF(LADO = 'ACTUAL', P, NULL)), 0), 0.0001) AS P_ACTUAL
    FROM DIST GROUP BY FEATURE, B
)
SELECT (SELECT ANY_VALUE(LOTE) FROM DRIFT_LOTE_ACTUAL) AS LOTE,
       FEATURE,
       ROUND(SUM((P_ACTUAL - P_BASE) * LN(P_ACTUAL / P_BASE)), 4) AS PSI,
       CASE WHEN SUM((P_ACTUAL - P_BASE) * LN(P_ACTUAL / P_BASE)) > 0.25 THEN 'DRIFT'
            WHEN SUM((P_ACTUAL - P_BASE) * LN(P_ACTUAL / P_BASE)) > 0.10 THEN 'VIGILAR'
            ELSE 'ESTABLE' END AS NIVEL
FROM PIV GROUP BY FEATURE;

INSERT INTO MODEL_DRIFT_METRICS SELECT CURRENT_TIMESTAMP(), LOTE, FEATURE, PSI, NIVEL FROM VW_DRIFT_PSI;
SELECT * FROM VW_DRIFT_PSI;          -- expected: MONTO and HORA ~0.00x, ESTABLE

-- -----------------------------------------------------------------------------
-- 3. Native alert: records an incident whenever the current batch drifts
-- -----------------------------------------------------------------------------
CREATE OR REPLACE ALERT ALRT_DRIFT_DETECTOR_FRAUDES
  WAREHOUSE = WH_AUDIT_SMALL
  SCHEDULE = '60 MINUTE'
  COMMENT = 'C06-AE-06: PSI > 0.25 en alguna feature del DETECTOR_FRAUDES'
  IF (EXISTS (SELECT 1 FROM SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.VW_DRIFT_PSI WHERE PSI > 0.25))
  THEN
    INSERT INTO SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.MODEL_DRIFT_ALERTS
    SELECT CURRENT_TIMESTAMP(), LOTE, FEATURE, PSI,
           'Drift en ' || FEATURE || ' (PSI ' || PSI || '): revisar/reentrenar DETECTOR_FRAUDES'
    FROM SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.VW_DRIFT_PSI WHERE PSI > 0.25;
ALTER ALERT ALRT_DRIFT_DETECTOR_FRAUDES RESUME;

-- -----------------------------------------------------------------------------
-- 4. DEMO — simulate drift: ticket inflation (+80 % in amounts) and fraud
--    pattern shifting to the night (hours 0–5)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DRIFT_LOTE_ACTUAL AS
SELECT 'LOTE_CON_DRIFT' AS LOTE,
       MONTO * 1.8 AS MONTO,
       IFF(UNIFORM(0, 9, RANDOM()) < 4, UNIFORM(0, 5, RANDOM()), HOUR(FECHA_TRANSACCION)) AS HORA,
       DAYOFWEEK(FECHA_TRANSACCION) AS DIA_SEMANA
FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS SAMPLE (1);

INSERT INTO MODEL_DRIFT_METRICS SELECT CURRENT_TIMESTAMP(), LOTE, FEATURE, PSI, NIVEL FROM VW_DRIFT_PSI;
SELECT * FROM VW_DRIFT_PSI;          -- expected: MONTO and HORA > 0.25, DRIFT

-- Don't wait for the schedule during the demo
EXECUTE ALERT ALRT_DRIFT_DETECTOR_FRAUDES;
-- After ~20 s:
SELECT * FROM MODEL_DRIFT_ALERTS ORDER BY DETECTADO_EN DESC;
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME
FROM TABLE(SUPERINTENDENCY_DEMO_DB.INFORMATION_SCHEMA.ALERT_HISTORY(
       SCHEDULED_TIME_RANGE_START => DATEADD('hour', -1, CURRENT_TIMESTAMP())))
ORDER BY SCHEDULED_TIME DESC;   -- STATE = TRIGGERED

-- Monitoring history for the slide / Power BI
SELECT * FROM MODEL_DRIFT_METRICS ORDER BY MEDIDO_EN, FEATURE;

-- -----------------------------------------------------------------------------
-- 5. STOP THE ALERT (live step, run it at the end of the demo, do not skip).
--    Keeps the drift history; stops the scheduled checks and their credits.
--    To resume later: ALTER ALERT ALRT_DRIFT_DETECTOR_FRAUDES RESUME;
-- -----------------------------------------------------------------------------
ALTER ALERT ALRT_DRIFT_DETECTOR_FRAUDES SUSPEND;
SHOW ALERTS LIKE 'ALRT_DRIFT_DETECTOR_FRAUDES' IN SCHEMA SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA;   -- expected: state = suspended
