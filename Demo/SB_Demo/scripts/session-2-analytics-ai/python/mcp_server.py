"""MCP server — external AI agent access to the SB demo lakehouse.

Evaluation items C06-PRE-06 & C06-AE-08: an external AI agent queries the
Lakehouse autonomously through the Model Context Protocol, respecting
role-based access.

One tool, ``query_customer_transactions``, is exposed over stdio for local MCP
clients such as Claude Desktop. It reads
``SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS`` with
the Snowflake Python Connector; credentials and the role come from environment
variables. Set ``SNOWFLAKE_ROLE=FR_BI_ANALYST`` to prove the agent only sees
masked PII (``MASK_CREDIT_CARD``) and RLS-restricted rows
(``RLS_BUSINESS_UNIT`` → RETAIL only); set ``FR_DEMO_ADMIN`` to show the
plaintext contrast.

Run:  python mcp_server.py        (stdio transport)
"""

from __future__ import annotations

import os
from datetime import date, datetime
from decimal import Decimal
from typing import Any

try:  # mcp 1.x
    from mcp.server.fastmcp import FastMCP as MCPServer
except ModuleNotFoundError:  # mcp 2.x renamed FastMCP -> MCPServer
    from mcp.server.mcpserver import MCPServer
import snowflake.connector

DB = "SUPERINTENDENCY_DEMO_DB"
SCHEMA = "CORE_BANKING_SCHEMA"
TABLE = "CREDIT_CARD_TRANSACTIONS"

mcp = MCPServer(
    "sb-lakehouse",
    instructions=(
        "Governed Snowflake lakehouse of the Superintendency of Banks demo. "
        "Use query_customer_transactions(rut) to inspect a customer's "
        "transactions. All results are filtered at query time by the "
        "connecting role's masking and row-level security policies."
    ),
)


def _connect() -> snowflake.connector.SnowflakeConnection:
    """Open a Snowflake session from environment variables (no keys in code)."""
    try:
        account = os.environ["SNOWFLAKE_ACCOUNT"]
        user = os.environ["SNOWFLAKE_USER"]
    except KeyError as exc:
        raise RuntimeError(
            f"missing required environment variable {exc.args[0]}"
        ) from None

    kwargs: dict[str, Any] = {
        "account": account,
        "user": user,
        "authenticator": os.environ.get("SNOWFLAKE_AUTHENTICATOR", "SNOWFLAKE_JWT"),
        "role": os.environ.get("SNOWFLAKE_ROLE", "FR_BI_ANALYST"),
        "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "WH_APP_XSMALL"),
        "database": DB,
        "schema": SCHEMA,
        "login_timeout": 20,
        "network_timeout": 60,
        # OCSP responder unreachable from this network (same workaround as
        # 01_train_fraud_model.py — otherwise connect() hangs).
        "disable_ocsp_checks": True,
    }

    key_path = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH")
    key_pem = os.environ.get("SNOWFLAKE_PRIVATE_KEY")
    if key_path:
        kwargs["private_key_file"] = key_path
    elif key_pem:
        from cryptography.hazmat.primitives import serialization

        kwargs["private_key"] = serialization.load_pem_private_key(
            key_pem.encode(), password=None
        ).private_bytes(
            serialization.Encoding.DER,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    else:
        raise RuntimeError(
            "set SNOWFLAKE_PRIVATE_KEY_PATH (or SNOWFLAKE_PRIVATE_KEY) for "
            "key-pair authentication"
        )

    conn = snowflake.connector.connect(**kwargs)
    # Persona isolation: the operator user also holds FR_DEMO_ADMIN and
    # FR_TERRAFORM, and Snowflake activates every role granted to the user as
    # a *secondary* role by default. Without this, an "FR_BI_ANALYST" session
    # would inherit FR_DATA_ENGINEER's raw-layer privileges (STAGING_SCHEMA)
    # even though FR_BI_ANALYST itself holds no staging grants. The agent must
    # see exactly the role it is configured with — and nothing else.
    conn.cursor().execute("USE SECONDARY ROLES NONE")
    return conn


def _jsonable(value: Any) -> Any:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return value


@mcp.tool()
def query_customer_transactions(rut: str, limit: int = 20) -> dict[str, Any]:
    """Return the credit-card transactions of one customer, identified by RUT.

    Args:
        rut: Chilean national ID (Rol Único Tributario), e.g. "5.000.081-8".
        limit: Maximum rows to return (1-100, newest first).

    The query runs as the connected role: masking policies hide card numbers
    and the row-access policy limits which business units are visible, so two
    roles receive different result sets from this same tool without any
    application changes.
    """
    rut = (rut or "").strip()
    if not rut:
        raise ValueError("rut must be a non-empty customer id")
    limit = max(1, min(int(limit), 100))

    conn = _connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE()")
        role, warehouse = cur.fetchone()

        sql = f"""
            SELECT
                ID_TRANSACCION, FECHA_TRANSACCION, MONTO, CATEGORIA,
                COMERCIO, CIUDAD, ESTADO, UNIDAD_NEGOCIO,
                NUMERO_TARJETA, RUT
            FROM {DB}.{SCHEMA}.{TABLE}
            WHERE RUT = %(rut)s
            ORDER BY FECHA_TRANSACCION DESC
            LIMIT {limit}
        """
        cur.execute(sql, {"rut": rut})
        columns = [col[0] for col in cur.description]
        rows = [
            {col: _jsonable(val) for col, val in zip(columns, row)}
            for row in cur.fetchall()
        ]
        cur.close()
    finally:
        conn.close()

    return {
        "role": role,
        "warehouse": warehouse,
        "table": f"{DB}.{SCHEMA}.{TABLE}",
        "rut": rut,
        "row_count": len(rows),
        "rows": rows,
        "governance": (
            "NUMERO_TARJETA is masked by MASK_CREDIT_CARD and rows are "
            "filtered by RLS_BUSINESS_UNIT for non-admin roles."
        ),
    }


if __name__ == "__main__":
    mcp.run()  # stdio transport — launches for the MCP client
