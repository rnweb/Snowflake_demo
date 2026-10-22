"""C08-AE-07: the external analyst connects from Python with the temporary user.

Credentials never come from the repo:
  SNOWFLAKE_ACCOUNT (env var or prompt), EXT_USER (default EXT_ANALISTA_PYME),
  EXT_PASSWORD (env var, otherwise asked with a hidden prompt)

    pip install snowflake-connector-python
    python check_external_access.py

Before revocation: masked rows, PYME only. After revocation: login fails.
"""
import getpass
import os
import sys

import snowflake.connector

account = os.environ.get("SNOWFLAKE_ACCOUNT") or input("Account identifier (ORG-CUENTA): ").strip()
user = os.environ.get("EXT_USER", "EXT_ANALISTA_PYME")
password = os.environ.get("EXT_PASSWORD") or getpass.getpass(f"Password de {user} (oculta): ")

try:
    conn = snowflake.connector.connect(
        account=account,
        user=user,
        password=password,
        role="FR_EXTERNAL_READER",
        warehouse="WH_APP_XSMALL",
        database="SUPERINTENDENCY_DEMO_DB",
        schema="CORE_BANKING_SCHEMA",
        session_parameters={"QUERY_TAG": "marketplace-external-check"},
    )
except snowflake.connector.errors.DatabaseError as exc:
    print(f"ACCESO DENEGADO -> {exc.msg}")
    sys.exit(1)

cur = conn.cursor()
cur.execute("USE SECONDARY ROLES NONE")

print("Filas visibles por unidad de negocio:")
for unidad, total in cur.execute(
    "SELECT UNIDAD_NEGOCIO, COUNT(*) FROM CREDIT_CARD_TRANSACTIONS GROUP BY 1"
):
    print(f"  {unidad}: {total}")

print("\nMuestra (PII enmascarada por la politica de Snowflake):")
for rut, tarjeta, monto in cur.execute(
    "SELECT RUT, NUMERO_TARJETA, MONTO FROM CREDIT_CARD_TRANSACTIONS LIMIT 5"
):
    print(f"  {rut} | {tarjeta} | {monto}")

try:
    cur.execute("SELECT COUNT(*) FROM CLIENT_PROFILE_DIM")
    print("\nCLIENT_PROFILE_DIM: accesible (NO esperado)")
except snowflake.connector.errors.ProgrammingError as exc:
    print(f"\nCLIENT_PROFILE_DIM fuera del pedido -> {exc.errno}: {exc.msg}")

conn.close()
