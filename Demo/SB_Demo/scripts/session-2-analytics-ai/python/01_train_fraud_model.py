"""Session 2 — 01: Snowpark ML fraud detection model.

Trains a RandomForest classifier on a fixed-size random SAMPLE of the dbt mart
(SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS; default
500 000 rows, TRAIN_SAMPLE_ROWS to change). The sample is materialised once so
training, evaluation and metrics use the same rows,
evaluates it and registers it in the Snowflake Model Registry
(RISK_ANALYTICS_SCHEMA) so it can be invoked from SQL:

    SELECT MODEL(<db>.<schema>.DETECTOR_FRAUDES, V1)!predict(<features>) FROM ...;

Execution model: this script is a CLIENT-SIDE ORCHESTRATOR. It runs on your
machine, connects to Snowflake, and issues the commands. The model FITTING runs
INSIDE Snowflake (Snowpark pushdown compute): snowflake-ml-python builds a
temporary stored procedure and the training executes on the warehouse. Data
does not leave Snowflake for training; only the metrics and the registered
model artifact are returned to the client.

Role: FR_DATA_ENGINEER (override: SNOWFLAKE_ROLE)
Warehouse: WH_APP_MEDIUM (override: SNOWFLAKE_WAREHOUSE). Because fitting runs
on this warehouse, the expensive WH_TRANSFORM_LARGE is reserved for workloads
that actually need it (trial-credit guardrail).

Dataset note: the metrics in the README and in the model's V1 metadata come from
an 18 000-row sample. The mart currently holds 50 000 000 rows (PG-06); this
script trains on a 500 000-row sample of it, so its metrics differ from V1.

Registry note: the default version is V1, which already exists in the account.
The script will NOT overwrite it. If V1 exists, it runs as evaluation only and
says so loudly. To register the sampled model, set MODEL_VERSION=V2 and update
the app / MCP / README references to the new version.

Note on labels: the synthetic dataset has no real fraud outcomes, so the
target ES_FRAUDE is a documented *proxy label* derived from business rules
(declined/high-value + suspicious category combinations).

Environment (no hardcoded users, accounts or key paths — fail-fast if unset):
    required : SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER and one of
               SNOWFLAKE_PRIVATE_KEY_PATH / SNOWFLAKE_PRIVATE_KEY
    optional : SNOWFLAKE_AUTHENTICATOR (default SNOWFLAKE_JWT),
               SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE,
               SNOWFLAKE_DISABLE_OCSP   (default true — OCSP responder is
               unreachable from the demo network; set false to enforce)

Usage (from the repository root, Python 3.12 venv):
    .venv/Scripts/python Demo/SB_Demo/scripts/session-2-analytics-ai/python/01_train_fraud_model.py
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
from snowflake.snowpark import functions as F

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
MODEL_VERSION = os.getenv("MODEL_VERSION", "V1")
# The new account mart has 50 000 000 rows: fitting a RandomForest on all of
# them does not fit in a MEDIUM warehouse. Train on a fixed-size random sample
# (default 500 000 rows, override with TRAIN_SAMPLE_ROWS). The sample is
# materialised once (cache_result) so train/test and the metrics see the same rows.
TRAIN_SAMPLE_ROWS = int(os.getenv("TRAIN_SAMPLE_ROWS", "500000"))

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
FROM {MART} SAMPLE ({TRAIN_SAMPLE_ROWS} ROWS)
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


def _require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        sys.exit(
            f"missing required environment variable {name} — set it in your "
            "shell (see 'Environment' in scripts/session-2-analytics-ai/README.md)"
        )
    return value


def build_session() -> Session:
    key_path = os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH")
    key_pem = os.getenv("SNOWFLAKE_PRIVATE_KEY")
    if key_path:
        with open(key_path, "rb") as fh:
            pem = fh.read()
    elif key_pem:
        pem = key_pem.encode()
    else:
        sys.exit(
            "set SNOWFLAKE_PRIVATE_KEY_PATH (path to your .p8 key) or "
            "SNOWFLAKE_PRIVATE_KEY (PEM contents) for key-pair authentication"
        )
    private_key = serialization.load_pem_private_key(
        pem, password=None
    ).private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    return Session.builder.configs(
        {
            "account": _require_env("SNOWFLAKE_ACCOUNT"),
            "user": _require_env("SNOWFLAKE_USER"),
            "authenticator": os.getenv("SNOWFLAKE_AUTHENTICATOR", "SNOWFLAKE_JWT"),
            "private_key": private_key,
            "role": os.getenv("SNOWFLAKE_ROLE", "FR_DATA_ENGINEER"),
            "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE", "WH_APP_MEDIUM"),
            "database": DB,
            "schema": REGISTRY_SCHEMA,
            "login_timeout": 30,
            "network_timeout": 60,
            "disable_ocsp_checks": os.getenv("SNOWFLAKE_DISABLE_OCSP", "true").lower()
            in {"1", "true", "yes"},
        }
    ).create()


def _existing_versions(session: Session) -> set:
    """Version names already registered for MODEL_NAME (empty if none)."""
    try:
        rows = session.sql(
            f"SHOW VERSIONS IN MODEL {DB}.{REGISTRY_SCHEMA}.{MODEL_NAME}"
        ).collect()
    except Exception:  # noqa: BLE001 - model does not exist yet
        return set()
    return {row["name"] for row in rows}


def main() -> int:
    session = build_session()
    try:
        ctx = session.sql(
            "SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE()"
        ).collect()[0]
        print(f"[1/5] connected as {ctx[0]} on {ctx[1]}")

        # Materialise the sample once: SAMPLE is non-deterministic, so a lazy
        # DataFrame would re-sample on every action (split, fit, metrics).
        base_df = session.sql(TRAIN_SQL).cache_result()
        counts = base_df.select(
            F.count(F.lit(1)), F.sum(F.col(LABEL_COL))
        ).collect()[0]
        print(
            f"[2/5] sample loaded: {counts[0]} rows of the mart "
            f"(TRAIN_SAMPLE_ROWS={TRAIN_SAMPLE_ROWS}), {counts[1]} proxy-fraud labels"
        )

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

        existing = _existing_versions(session)
        if MODEL_VERSION in existing:
            # Never overwrite a registered version silently: the app, MCP and
            # README all read V1. This run is evaluation only.
            print(
                f"[5/5] NOT REGISTERED: {MODEL_NAME} {MODEL_VERSION} already exists "
                f"(versions: {sorted(existing)}). The registry is unchanged; the "
                "metrics above are for THIS sampled run only. To register it, "
                "rerun with MODEL_VERSION=V2 and update the references."
            )
        else:
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
            except Exception:  # noqa: BLE001
                import traceback

                traceback.print_exc()
                print("[5/5] registration FAILED (see traceback above)")
                return 1

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
