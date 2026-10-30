"""Concurrent load generator for C02-AE-03 / C02-AE-09 / C09-AE-02.

Opens N parallel sessions against one warehouse and runs analytical queries on
the 50M-row mart with the result cache disabled, tagging every query so the
SQL in session-5/sql reads the before/after evidence from QUERY_HISTORY.

    pip install snowflake-connector-python
    python load_test.py --warehouse WH_CARGA_ELASTICA --sessions 16 --rounds 3 --tag carga-antes

Credentials never come from the repo. Authentication (same contract as the
other session scripts):
    required : SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER and one of
               SNOWFLAKE_PRIVATE_KEY_PATH (.p8) / SNOWFLAKE_PRIVATE_KEY (PEM)  [key-pair, preferred]
    fallback : SNOWFLAKE_PASSWORD, or a hidden prompt if no key is set
    optional : SNOWFLAKE_ROLE (default FR_DATA_ENGINEER)
"""
import argparse
import getpass
import os
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import snowflake.connector
from cryptography.hazmat.primitives import serialization

QUERIES = [
    "SELECT UNIDAD_NEGOCIO, CATEGORIA, COUNT(*), SUM(MONTO), AVG(MONTO) "
    "FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS GROUP BY 1, 2",
    "SELECT CIUDAD, ESTADO, COUNT(*), APPROX_PERCENTILE(MONTO, 0.95) "
    "FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS GROUP BY 1, 2",
    "SELECT DATE_TRUNC('month', FECHA_TRANSACCION) AS MES, COUNT(DISTINCT ID_TARJETA), SUM(MONTO) "
    "FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS GROUP BY 1",
]


def worker(conn_args, warehouse, tag, rounds, worker_id):
    times = []
    conn = snowflake.connector.connect(**conn_args, warehouse=warehouse,
                                       session_parameters={"QUERY_TAG": tag, "USE_CACHED_RESULT": False})
    try:
        cur = conn.cursor()
        for r in range(rounds):
            sql = QUERIES[(worker_id + r) % len(QUERIES)]
            t0 = time.perf_counter()
            cur.execute(sql)
            cur.fetchall()
            times.append(time.perf_counter() - t0)
    finally:
        conn.close()
    return times


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--warehouse", required=True)
    ap.add_argument("--sessions", type=int, default=16)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--tag", required=True, help="QUERY_TAG, e.g. carga-antes / carga-despues")
    a = ap.parse_args()

    account = os.environ.get("SNOWFLAKE_ACCOUNT") or input("Account (ORG-CUENTA): ").strip()
    user = os.environ.get("SNOWFLAKE_USER") or input("Usuario: ").strip()
    role = os.environ.get("SNOWFLAKE_ROLE", "FR_DATA_ENGINEER")
    conn_args = dict(account=account, user=user, role=role,
                     client_session_keep_alive=False,
                     disable_ocsp_checks=os.environ.get("SNOWFLAKE_DISABLE_OCSP", "true").lower()
                     in {"1", "true", "yes"},
                     login_timeout=30)

    key_path = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH")
    key_pem = os.environ.get("SNOWFLAKE_PRIVATE_KEY")
    if key_path or key_pem:
        pem = open(key_path, "rb").read() if key_path else key_pem.encode()
        conn_args["private_key"] = serialization.load_pem_private_key(pem, password=None).private_bytes(
            serialization.Encoding.DER,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        conn_args["authenticator"] = os.environ.get("SNOWFLAKE_AUTHENTICATOR", "SNOWFLAKE_JWT")
    else:
        conn_args["password"] = os.environ.get("SNOWFLAKE_PASSWORD") or getpass.getpass(
            f"Password de {user} (oculta): ")

    print(f"{a.sessions} sesiones x {a.rounds} rondas en {a.warehouse} (tag={a.tag}) ...")
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=a.sessions) as ex:
        results = list(ex.map(lambda i: worker(conn_args, a.warehouse, a.tag, a.rounds, i), range(a.sessions)))
    wall = time.perf_counter() - t0
    all_t = sorted(t for r in results for t in r)
    p95 = all_t[int(0.95 * (len(all_t) - 1))]
    print(f"queries={len(all_t)}  promedio={statistics.mean(all_t):.1f}s  p95={p95:.1f}s  total={wall:.1f}s")
    print("Evidencia completa: session-5/sql/02_carga_multicluster_gargalo.sql, sección 4.")


if __name__ == "__main__":
    main()
