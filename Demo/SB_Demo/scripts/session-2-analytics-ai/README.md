# Session 2 — Analytics, MLOps & GenAI

**Audience:** Risk Analysts, Data Scientists & Platform Engineers —
Superintendency of Banks.

This session shows how the platform moves from *governed data* to
*operational intelligence*:

1. **Snowpark ML** — RandomForest fraud detector trained on the dbt mart and
   registered in the Snowflake Model Registry (`DETECTOR_FRAUDES`, V1),
   callable from SQL
2. **Cortex AI (español)** — `CORTEX.SUMMARIZE`, `CORTEX.TRANSLATE` and
   `CORTEX.COMPLETE` over the transactional data (Spanish prompts/outputs)
3. **Streamlit (español)** — *Panel de Prevención de Fraude*: KPIs, charts,
   model-inference form and a Cortex text box (**deployment requires explicit
   human approval**)
4. **MCP server** — one governed tool (`query_customer_transactions`) that an
   external AI client (e.g. Claude Desktop) queries over the Model Context
   Protocol; Snowflake enforces masking + RLS per connecting role

## Files

| File | Purpose |
|------|---------|
| `python/01_train_fraud_model.py` | Feature SQL, training, evaluation, registry, SQL-inference check |
| `sql/02_cortex_ai_features.sql`  | Four Cortex calls (Spanish) over `CREDIT_CARD_TRANSACTIONS` |
| `streamlit_app.py`               | Streamlit app source (Spanish UI) — **not deployed by automation** |
| `python/mcp_server.py`           | stdio MCP server exposing `query_customer_transactions(rut)` for AI clients |

## Prerequisites

- Infrastructure applied (`cd Demo/SB_Demo/terraform && terraform
  apply`), including the Session 2 grants:
  - `CREATE MODEL`, `CREATE FUNCTION` on `RISK_ANALYTICS_SCHEMA`
    (model registration) — `security.tf`
  - `USAGE` on `WH_APP_XSMALL`, `USAGE`+`CREATE STREAMLIT` and stage
    `READ`/`WRITE` on `CORTEX_NATIVE_APP_DB.PUBLIC` (app deployment)
- Python **3.12** virtualenv at the repository root (snowflake-ml-python has
  no Python 3.14 wheels):

  ```bash
  py -3.12 -m venv .venv
  .venv\Scripts\python -m pip install snowflake-ml-python snowflake-snowpark-python scikit-learn streamlit plotly pandas
  ```

- Environment variables (user scope, same as Session 1):
  `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT`,
  `SNOWFLAKE_PRIVATE_KEY_PATH`
- Session 1 executed (the mart `CREDIT_CARD_TRANSACTIONS` must exist)

## Step 1 — Train & register the fraud model

From the repository root:

```bash
.venv\Scripts\python -u Demo/SB_Demo/scripts/session-2-analytics-ai/python/01_train_fraud_model.py
```

Expected output (role `FR_DATA_ENGINEER`, warehouse `WH_CORTEX_LARGE`):

```
[1/5] connected as FR_DATA_ENGINEER on WH_CORTEX_LARGE
[2/5] mart loaded: 18000 rows, 1675 proxy-fraud labels
[3/5] RandomForest trained (80/20 split, seed=42)
[4/5] evaluation: EVALUADOS=3651 ACCURACY=0.9310 RECALL=0.4404 PRECISION=0.7608
[5/5] registered SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES (V1)

--- SQL inference example (model is callable from SQL) ---
SELECT MODEL(SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES, V1)!predict(
    MONTO => 480000, HORA => 2, DIA_SEMANA => 6, FIN_DE_SEMANA => 1,
    CATEGORIA_ALTO_RIESGO => 1, UNIDAD_NEGOCIO_COD => 1
) AS PREDICCION
FROM (SELECT 1 AS MUESTRA)
result: Row(PREDICCION='... "PRED_ES_FRAUDE": 1 ...')
```

Notes for the presenter (all handled inside the script):

- **Label**: the synthetic data has no real fraud outcomes, so `ES_FRAUDE` is
  a documented *proxy label* (declined ≥ 250 000 or any ≥ 400 000 with
  suspicious category rules).
- **pyarrow**: the sklearn model specification omits `pyarrow` from the
  temporary training procedure's package list; the script injects the
  channel-supported `pyarrow==18.1.0` (see comment in the script).
- **OCSP**: connections set `disable_ocsp_checks=True` because the OCSP
  responder is unreachable from this network (otherwise `connect()` hangs).
- **Windows encoding**: stdout/stderr are forced to UTF-8 so the ❌/✔ markers
  of `snowflake-ml-python` progress bars cannot mask real errors.
- Re-running is safe: a second run reports
  `registration skipped` if version `V1` already exists.

## Step 2 — Cortex AI in Spanish

`sql/02_cortex_ai_features.sql` contains four statements (comments and output
in Spanish):

1. `SNOWFLAKE.CORTEX.SUMMARIZE` — resumen ejecutivo de las transacciones ≥
   400 000 (lista de 30, LISTAGG)
2. `SNOWFLAKE.CORTEX.TRANSLATE` — encabezado de informe ES → EN
3. `SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', …)` — veredicto de riesgo
   `RIESGO: ALTO|MEDIO|BAJO` con contexto de las 10 peores transacciones
   (patrón RAC sobre el mart, sin embeddings)
4. `SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b', …)` — extracción estructurada
   JSON para un sistema de alertas

Run them from a Snowsight worksheet (or any SQL client) as
**`FR_DATA_ENGINEER`** on **`WH_CORTEX_LARGE`**.

> **Limitación de la cuenta demo:** esta cuenta es de prueba (*trial*) y
> Snowflake devuelve `399258 (0A000): AI function ... is not available for
> trial accounts` para las tres funciones. Las cuatro consultas están
> verificadas: compilan, resuelven la función y solo chocan con esa puerta de
> licencia. En una cuenta estándar producen los textos descritos arriba. El
> resto de la demo (datos, RBAC, modelo ML, app) no depende de Cortex.

## Step 3 — Streamlit app (human approval required)

`streamlit_app.py` (todo el texto de la interfaz en español):

- KPIs: transacciones, monto total, rechazadas, alertas de riesgo
- Gráficos: monto por categoría (barras), distribución por estado (donut),
  evolución mensual (línea)
- Tabla de las 20 transacciones de mayor monto (sin columnas sensibles)
- **Evaluador de riesgo**: formulario que invoca
  `MODEL(..., V1)!predict(...)` desde SQL y muestra ALERTA / sin alerta
- **Resumen con Cortex**: caja de texto → `CORTEX.SUMMARIZE` (aviso amable en
  cuentas trial)

> 🚧 **Guardrail:** the automation never deploys apps. After explicit human
> review and approval, the presenter runs the following as
> **`FR_DATA_ENGINEER`**:

```sql
PUT file://Demo/SB_Demo/scripts/session-2-analytics-ai/streamlit_app.py
  @CORTEX_NATIVE_APP_DB.PUBLIC.STREAMLIT_STAGE OVERWRITE=TRUE;

CREATE OR REPLACE STREAMLIT PANEL_PREVENCION_FRAUDE
  ROOT_LOCATION = '@CORTEX_NATIVE_APP_DB.PUBLIC.STREAMLIT_STAGE'
  MAIN_FILE      = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'WH_APP_XSMALL'
  COMMENT = 'Panel de Prevención de Fraude — demo Superintendencia de Bancos';
```

The app connects through `st.connection("snowflake")` and switches the session
to `FR_DATA_ENGINEER` when the deployment role allows it (otherwise it keeps
the deployment role's privileges).

## Step 4 — MCP server for an external AI agent (C06-PRE-06 & C06-AE-08)

`python/mcp_server.py` exposes a single tool over stdio:

```
query_customer_transactions(rut, limit=20)  →  rows of
SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
```

The tool opens a fresh Snowflake session per call using only environment
variables (no credentials in code) and runs `USE SECONDARY ROLES NONE`, so the
agent sees **exactly** the configured role — masking and row-level security are
enforced inside Snowflake, never by the agent.

Install the protocol library (once, into the same virtualenv as Step 1):

```bash
.venv\Scripts\python -m pip install mcp
```

Run manually (stdio transport; the MCP client spawns it for you):

```bash
set SNOWFLAKE_ACCOUNT=RBGXIGI-UAC53151
set SNOWFLAKE_USER=OPERATIONS
set SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
set SNOWFLAKE_PRIVATE_KEY_PATH=%USERPROFILE%\rsa_key.p8
set SNOWFLAKE_ROLE=FR_BI_ANALYST
set SNOWFLAKE_WAREHOUSE=WH_APP_XSMALL
.venv\Scripts\python -u Demo/SB_Demo/scripts/session-2-analytics-ai/python/mcp_server.py
```

`SNOWFLAKE_ROLE` defaults to `FR_BI_ANALYST` and `SNOWFLAKE_WAREHOUSE` to
`WH_APP_XSMALL`; the MCP server always reads from
`CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS`.

### Connect Claude Desktop

Add to the `mcpServers` block of Claude Desktop's config
(`claude_desktop_config.json` — path per the
[Anthropic docs](https://support.claude.com/en/articles/11175166-getting-started-using-mcp-with-claude-desktop)):

```json
{
  "mcpServers": {
    "snowflake-demo": {
      "command": "C:\\path\\to\\.venv\\Scripts\\python.exe",
      "args": ["-u", "Demo/SB_Demo/scripts/session-2-analytics-ai/python/mcp_server.py"],
      "env": {
        "SNOWFLAKE_ACCOUNT": "RBGXIGI-UAC53151",
        "SNOWFLAKE_USER": "OPERATIONS",
        "SNOWFLAKE_AUTHENTICATOR": "SNOWFLAKE_JWT",
        "SNOWFLAKE_PRIVATE_KEY_PATH": "C:\\Users\\<you>\\rsa_key.p8",
        "SNOWFLAKE_ROLE": "FR_BI_ANALYST",
        "SNOWFLAKE_WAREHOUSE": "WH_APP_XSMALL"
      }
    }
  }
}
```

Restart Claude Desktop, then in the chat ask e.g.
**«¿Cuántas transacciones tiene el RUT 5.017.491-3?»** — Claude calls the tool
and reads back the numbers.

### Presenter demo script (governed vs. plaintext)

| # | Ask / do | Expected result |
|---|----------|-----------------|
| 1 | Tool call as `FR_BI_ANALYST`, RUT `5.017.491-3` (retail customer) | `row_count` ≈ 50, every `NUMERO_TARJETA` = `****-****-****-****`, `UNIDAD_NEGOCIO` = `RETAIL` only — **masked + RLS** |
| 2 | Same role, RUT `5.000.081-8` (non-retail customer) | `row_count: 0` — the row-access policy hides the customer entirely (45 rows exist) |
| 3 | Change `SNOWFLAKE_ROLE` to `FR_DEMO_ADMIN`, restart Claude Desktop, repeat 1–2 | plaintext PANs (e.g. `3714-4947-8712-5521`) and 45 rows for `5.000.081-8` — same tool, **zero app changes** |
| 4 | (Optional) ask the agent to read `STAGING_SCHEMA` | fails with `002003` — `FR_BI_ANALYST` holds no staging grants, and the session has secondary roles disabled |

The return payload always echoes `role`, `warehouse` and a `governance` note,
so the presenter can show *who* answered, not just *what*.

## Related reading

- Session 1 (data foundation): `../session-1-lakehouse/README.md`
- Execution order & guardrails: `../../prompts/03-execution-validation.md`
