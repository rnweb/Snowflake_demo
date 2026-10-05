"""Session 2 — 01: Snowpark ML fraud detection model.

Trains a RandomForest classifier on the dbt mart
(SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS),
evaluates it and registers it in the Snowflake Model Registry
(RISK_ANALYTICS_SCHEMA) so it can be invoked from SQL:

    SELECT MODEL(<db>.<schema>.DETECTOR_FRAUDES, V1)!predict(<features>) FROM ...;

Role: FR_DATA_ENGINEER | Warehouse: WH_CORTEX_LARGE

Note on labels: the synthetic dataset has no real fraud outcomes, so the
target ES_FRAUDE is a documented *proxy label* derived from business rules
(declined/high-value + suspicious category combinations).

Usage (from the repository root, Python 3.12 venv):
    .venv/Scripts/python scripts/session-2-analytics-ai/python/01_train_fraud_model.py
"""

import os
import sys

# Windows console/pipe default encodings (cp1252) cannot encode the markers
# snowflake-ml-python draws on its progress bars, which would mask the real
# error behind a UnicodeEncodeError. Force UTF-8 for stdout/stderr.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

from cryptography.hazmat.primitives import serialization
from snowflake.ml.modeling._internal import model_specifications as _model_specifications
from snowflake.ml.modeling.ensemble import RandomForestClassifier
from snowflake.ml.registry import Registry
from snowflake.snowpark import Session

# Workaround: Snowflake ML's sklearn model specification omits pyarrow from the
# package list of the temporary training procedure, but the in-database python
# connector needs pyarrow to materialize to_pandas() results (255002 otherwise).
# The Snowflake conda channel ships pyarrow 18.1.0 for Python 3.12.
CHANNEL_PYARROW = "pyarrow==18.1.0"

_build_spec = _model_specifications.ModelSpecificationsBuilder.build.__func__


@classmethod
def _build_spec_with_pyarrow(cls, model: object):
    spec = _build_spec(cls, model)
    if not any(dep.startswith("pyarrow==") for dep in spec.pkgDependencies):
        spec.pkgDependencies.append(CHANNEL_PYARROW)
    return spec


_model_specifications.ModelSpecificationsBuilder.build = _build_spec_with_pyarrow

DB = "SUPERINTENDENCY_DEMO_DB"
MART = f"{DB}.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS"
REGISTRY_SCHEMA = "RISK_ANALYTICS_SCHEMA"
MODEL_NAME = "DETECTOR_FRAUDES"
MODEL_VERSION = "V1"

FEATURE_COLS = [
    "MONTO",
    "HORA",
    "DIA_SEMANA",
    "FIN_DE_SEMANA",
    "CATEGORIA_ALTO_RIESGO",
    "UNIDAD_NEGOCIO_COD",
]
LABEL_COL = "ES_FRAUDE"
PRED_COL = "PRED_ES_FRAUDE"

TRAIN_SQL = f"""
SELECT
    MONTO,
    HOUR(FECHA_TRANSACCION)                                   AS HORA,
    DAYOFWEEK(FECHA_TRANSACCION)                              AS DIA_SEMANA,
    CASE WHEN DAYOFWEEK(FECHA_TRANSACCION) IN (0, 6) THEN 1 ELSE 0 END
                                                              AS FIN_DE_SEMANA,
    CASE WHEN CATEGORIA IN ('ELECTRONICA', 'VIAJES') THEN 1 ELSE 0 END
                                                              AS CATEGORIA_ALTO_RIESGO,
    CASE UNIDAD_NEGOCIO
        WHEN 'CORPORATIVO' THEN 3
        WHEN 'PYME'         THEN 2
        WHEN 'RETAIL'       THEN 1
        ELSE 0
    END                                                       AS UNIDAD_NEGOCIO_COD,
    CASE
        WHEN ESTADO = 'RECHAZADA' AND MONTO >= 250000 THEN 1
        WHEN ESTADO = 'PENDIENTE' AND MONTO >= 400000 THEN 1
        WHEN ESTADO = 'APROBADA'
             AND MONTO >= 400000
             AND CATEGORIA IN ('ELECTRONICA', 'VIAJES')       THEN 1
        ELSE 0
    END                                                       AS ES_FRAUDE
FROM {MART}
"""

MODEL_CALL_SQL = f"""
SELECT MODEL({DB}.{REGISTRY_SCHEMA}.{MODEL_NAME}, {MODEL_VERSION})!predict(
    MONTO => 480000,
    HORA => 2,
    DIA_SEMANA => 6,
    FIN_DE_SEMANA => 1,
    CATEGORIA_ALTO_RIESGO => 1,
    UNIDAD_NEGOCIO_COD => 1
) AS PREDICCION
FROM (SELECT 1 AS MUESTRA)
"""


def build_session() -> Session:
    key_path = os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]
    with open(key_path, "rb") as fh:
        private_key = serialization.load_pem_private_key(fh.read(), password=None).private_bytes(
            serialization.Encoding.DER,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    return Session.builder.configs(
        {
            "account": os.environ["SNOWFLAKE_ACCOUNT"],
            "user": os.environ["SNOWFLAKE_USER"],
            "authenticator": "SNOWFLAKE_JWT",
            "private_key": private_key,
            "role": "FR_DATA_ENGINEER",
            "warehouse": "WH_CORTEX_LARGE",
            "database": DB,
            "schema": REGISTRY_SCHEMA,
            "login_timeout": 30,
            "network_timeout": 60,
            "disable_ocsp_checks": True,
        }
    ).create()


def main() -> int:
    session = build_session()
    try:
        ctx = session.sql(
            "SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE()"
        ).collect()[0]
        print(f"[1/5] connected as {ctx[0]} on {ctx[1]}")

        base_df = session.sql(TRAIN_SQL)
        counts = session.sql(
            f"SELECT COUNT(*), SUM(ES_FRAUDE) FROM ({TRAIN_SQL.rstrip()})"
        ).collect()[0]
        print(f"[2/5] mart loaded: {counts[0]} rows, {counts[1]} proxy-fraud labels")

        train_df, test_df = base_df.random_split([0.8, 0.2], seed=42)

        model = RandomForestClassifier(
            n_estimators=100,
            random_state=42,
            input_cols=FEATURE_COLS,
            label_cols=[LABEL_COL],
            output_cols=[PRED_COL],
        )
        model.fit(train_df)
        print("[3/5] RandomForest trained (80/20 split, seed=42)")

        predictions = model.predict(test_df)
        predictions.createOrReplaceTempView("TMP_EVAL_FRAUDES")
        metrics = session.sql(
            """
            SELECT
                COUNT(*)                                                    AS EVALUADOS,
                ROUND(AVG(CASE WHEN PRED_ES_FRAUDE = ES_FRAUDE
                               THEN 1 ELSE 0 END), 4)                       AS ACCURACY,
                ROUND(AVG(CASE WHEN ES_FRAUDE = 1 AND PRED_ES_FRAUDE = 1
                               THEN 1.0 ELSE 0 END)
                      / NULLIF(AVG(CASE WHEN ES_FRAUDE = 1
                                        THEN 1.0 ELSE 0 END), 0), 4)        AS RECALL,
                ROUND(AVG(CASE WHEN ES_FRAUDE = 1 AND PRED_ES_FRAUDE = 1
                               THEN 1.0 ELSE 0 END)
                      / NULLIF(AVG(CASE WHEN PRED_ES_FRAUDE = 1
                                        THEN 1.0 ELSE 0 END), 0), 4)        AS PRECISION
            FROM TMP_EVAL_FRAUDES
            """
        ).collect()[0]
        print(
            f"[4/5] evaluation: EVALUADOS={metrics[0]} "
            f"ACCURACY={metrics[1]} RECALL={metrics[2]} PRECISION={metrics[3]}"
        )

        registry = Registry(
            session=session,
            database_name=DB,
            schema_name=REGISTRY_SCHEMA,
        )
        try:
            registry.log_model(
                model_name=MODEL_NAME,
                version_name=MODEL_VERSION,
                model=model,
                metrics={
                    "accuracy": float(metrics[1]),
                    "recall": float(metrics[2]),
                    "precision": float(metrics[3]),
                },
                comment=(
                    "Detector de transacciones sospechosas (RandomForest) — "
                    "etiqueta proxy ES_FRAUDE, datos sintéticos de la demo."
                ),
            )
            print(f"[5/5] registered {DB}.{REGISTRY_SCHEMA}.{MODEL_NAME} ({MODEL_VERSION})")
        except Exception:  # noqa: BLE001 - idempotent re-runs
            import traceback

            traceback.print_exc()
            print("[5/5] registration skipped (see traceback above)")

        print("\n--- SQL inference example (model is callable from SQL) ---")
        print(MODEL_CALL_SQL.strip())
        result = session.sql(MODEL_CALL_SQL).collect()
        for row in result:
            print("result:", row)

        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
