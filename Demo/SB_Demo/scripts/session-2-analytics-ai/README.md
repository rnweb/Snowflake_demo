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
   human approval**; deployed 2026-10-15 via `sql/04_deploy_streamlit.sql`)
4. **MCP server** — one governed tool (`query_customer_transactions`) that an
   external AI client (e.g. Claude Desktop) queries over the Model Context
   Protocol; Snowflake enforces masking + RLS per connecting role
5. **RAG vector store** — Cortex embeddings + document retrieval in
   `SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE` for vector search and context
   grounding before generation

> **Required preparation before the SQL block 5 (vector store):** run
> `terraform apply` first so the `CORTEX_VECTOR_STORE` schema exists; otherwise
> Snowflake returns `002043` when the block tries to create or write to the
> vector-store table.

## Files

| File | Purpose |
|------|---------|
| `python/01_train_fraud_model.py` | Feature SQL, training, evaluation, registry, SQL-inference check |
| `sql/02_cortex_ai_features.sql`  | Five Cortex / RAG blocks (Spanish) over the mart and the vector store |
| `sql/04_deploy_streamlit.sql`    | PUT + `CREATE STREAMLIT` (human-gated deploy step; run from repo root with snowsql) |
| `streamlit_app.py`               | Streamlit app source (Spanish UI) — deployed by `sql/04_deploy_streamlit.sql` after human approval |
| `python/mcp_server.py`           | stdio MCP server exposing `query_customer_transactions(rut)` for AI clients |

## Prerequisites

- Infrastructure applied (`cd Demo/SB_Demo/terraform && terraform
  apply`), including the Session 2 grants:
  - `CREATE MODEL`, `CREATE FUNCTION` on `RISK_ANALYTICS_SCHEMA`
    (model registration) — `security.tf`
  - `USAGE` + `CREATE TABLE` / `CREATE VIEW` / `MODIFY` on
    `CORTEX_VECTOR_STORE` (vector store) — `security.tf`
  - `USAGE` on `WH_APP_MEDIUM`, `USAGE`+`CREATE STREAMLIT` and stage
    `READ`/`WRITE` on `CORTEX_NATIVE_APP_DB.PUBLIC` (app deployment)
- Python **3.12** virtualenv at the repository root (snowflake-ml-python has
  no Python 3.14 wheels):

  ```bash
  py -3.12 -m venv .venv
  .venv\Scripts\python -m pip install snowflake-ml-python snowflake-snowpark-python scikit-learn streamlit plotly pandas
  ```

- Environment variables (user scope, same as Session 1) — scripts read
  **only** from the environment (fail-fast, no hardcoded accounts/users/keys):
  - required: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`,
    `SNOWFLAKE_PRIVATE_KEY_PATH` (or `SNOWFLAKE_PRIVATE_KEY` = PEM contents)
  - optional: `SNOWFLAKE_AUTHENTICATOR` (default `SNOWFLAKE_JWT`),
    `SNOWFLAKE_ROLE` (train: `FR_DATA_ENGINEER`, MCP: `FR_BI_ANALYST`),
    `SNOWFLAKE_WAREHOUSE` (default `WH_APP_MEDIUM`),
    `SNOWFLAKE_DISABLE_OCSP` (default `true` — OCSP responder unreachable
    from this network; set `false` to enforce OCSP validation)
- Session 1 executed (the mart `CREDIT_CARD_TRANSACTIONS` must exist)

## Step 1 — Train & register the fraud model

From the repository root:

```bash
.venv\Scripts\python -u Demo/SB_Demo/scripts/session-2-analytics-ai/python/01_train_fraud_model.py
```

Expected output (role `FR_DATA_ENGINEER`, warehouse `WH_APP_MEDIUM` — the
MEDIUM default keeps costs bounded; override with `SNOWFLAKE_WAREHOUSE`,
e.g. `WH_TRANSFORM_LARGE` for parallel training benches):

```
[1/5] connected as FR_DATA_ENGINEER on WH_APP_MEDIUM
[2/5] mart loaded: 18000 rows, 1675 proxy-fraud labels
[3/5] RandomForest trained (80/20 split, seed=42)
[4/5] evaluation: EVALUADOS=3651 ACCURACY=0.9310 RECALL=0.4404 PRECISION=0.7608
[5/5] registered SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES (V1)
```

> Transcript of the original 18 000-row training run (labels/eval as shown).
> The mart holds **50 000 000** rows since PG-06 (2026-10-21) — retrain
> `python/01_train_fraud_model.py` to refresh the evaluation set.

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

`sql/02_cortex_ai_features.sql` contains five blocks (comments and output in
Spanish):

1. `AI_SUMMARIZE` — resumen ejecutivo de las transacciones ≥
   400 000 (lista de 30, LISTAGG)
2. `AI_TRANSLATE` — encabezado de informe ES → EN
3. `AI_COMPLETE('llama3.1-70b', …)` — veredicto de riesgo
   `RIESGO: ALTO|MEDIO|BAJO` con contexto de las 10 peores transacciones
   (patrón RAC sobre el mart, sin embeddings)
4. `AI_COMPLETE('llama3.1-8b', …)` — extracción estructurada
   JSON para un sistema de alertas
5. `CORTEX_VECTOR_STORE` RAG block — embeddings (`AI_EMBED`), vector
   retrieval (`VECTOR_INNER_PRODUCT`) and grounded answers via
   `AI_COMPLETE` + `AI_EXTRACT` (mode `question answering`)

Run them from a Snowsight worksheet (or any SQL client) as
**`FR_DATA_ENGINEER`** on **`WH_APP_MEDIUM`** (or `WH_TRANSFORM_LARGE` when the
account has credits to spare — never the default).

> **Trial Account (Credit Card Attached) (verificado):** los cinco bloques se ejecutaron de
> extremo a extremo el 2026-10-21 en la Trial Account (Credit Card Attached) `zkdcmqh-fjc41457`:
> resumen, traducción, veredicto RAC y JSON (bloques 1-4) más el RAG completo
> (bloque 5: tabla `CORTEX_VECTOR_STORE.DOCUMENTS`, embeddings `AI_EMBED`
> 768-d, recuperación por `VECTOR_INNER_PRODUCT` y respuesta generada con
> `AI_COMPLETE`/`AI_EXTRACT`). **Nota para cuentas nuevas:** las funciones
> heredadas `SNOWFLAKE.CORTEX.*` están bloqueadas (error `399270`), por lo que
> el script usa el espacio de nombres moderno `AI_*` (`AI_SUMMARIZE`,
> `AI_TRANSLATE`, `AI_COMPLETE`, `AI_EMBED`, `AI_EXTRACT`). El resto de la
> demo (datos, RBAC, modelo ML, app) no depende de Cortex.

## Step 3 — Streamlit app (human approval required)

`streamlit_app.py` (todo el texto de la interfaz en español):

- KPIs: transacciones, monto total, rechazadas, alertas de riesgo
- Gráficos: monto por categoría (barras), distribución por estado (donut),
  evolución mensual (línea)
- Tabla de las 20 transacciones de mayor monto (sin columnas sensibles)
- **Evaluador de riesgo**: formulario que invoca
  `MODEL(..., V1)!predict(...)` desde SQL y muestra ALERTA / sin alerta
- **Resumen con Cortex**: caja de texto → `AI_SUMMARIZE` (aviso amable si la
  función no está disponible en la cuenta)

> 🚧 **Guardrail:** the automation never deploys apps. After explicit human
> review and approval of `streamlit_app.py`, the presenter runs
> `sql/04_deploy_streamlit.sql` from the repository root with snowsql (`PUT`
> is a client command — it does not run in a Snowsight worksheet) as
> **`FR_DATA_ENGINEER`**. **Deployed 2026-10-15**: `SHOW STREAMLITS IN
> DATABASE CORTEX_NATIVE_APP_DB` returns `PANEL_PREVENCION_FRAUDE`
> (`owner: FR_DATA_ENGINEER`, `query_warehouse: WH_APP_MEDIUM`). Redeploying
> (`CREATE OR REPLACE`) still requires fresh human approval.

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
set SNOWFLAKE_ACCOUNT=zkdcmqh-fjc41457
set SNOWFLAKE_USER=OPERATIONS
set SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
set SNOWFLAKE_PRIVATE_KEY_PATH=%USERPROFILE%\rsa_key.p8
set SNOWFLAKE_ROLE=FR_BI_ANALYST
set SNOWFLAKE_WAREHOUSE=WH_APP_MEDIUM
.venv\Scripts\python -u Demo/SB_Demo/scripts/session-2-analytics-ai/python/mcp_server.py
```

`SNOWFLAKE_ROLE` defaults to `FR_BI_ANALYST` and `SNOWFLAKE_WAREHOUSE` to
`WH_APP_MEDIUM`; the MCP server always reads from
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
        "SNOWFLAKE_ACCOUNT": "zkdcmqh-fjc41457",
        "SNOWFLAKE_USER": "OPERATIONS",
        "SNOWFLAKE_AUTHENTICATOR": "SNOWFLAKE_JWT",
        "SNOWFLAKE_PRIVATE_KEY_PATH": "C:\\Users\\<you>\\rsa_key.p8",
        "SNOWFLAKE_ROLE": "FR_BI_ANALYST",
        "SNOWFLAKE_WAREHOUSE": "WH_APP_MEDIUM"
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
| 1 | Tool call as `FR_BI_ANALYST`, RUT `5.017.491-3` (retail customer, `limit=100`) | `row_count: 76` (76 rows exist; default `limit=20` returns 20), `RUT` column shows the deterministic pseudonym, and the customer is within the retail slice |
| 2 | Same role, RUT `5.000.081-8` (non-retail customer) | `row_count: 0` — the row-access policy hides the customer entirely (45 rows exist) |
| 3 | Change `SNOWFLAKE_ROLE` to `FR_DEMO_ADMIN`, restart Claude Desktop, repeat 1–2 | plaintext RUTs and PANs (e.g. `4111-1119-9180-8125`), `rut_filter: plaintext`, and 45 rows for `5.000.081-8` |
| 4 | (Optional) ask the agent to read `STAGING_SCHEMA` | fails with `002003` — `FR_BI_ANALYST` holds no staging grants, and the session has secondary roles disabled |

**Expected MCP governance checks:**
- `NUMERO_TARJETA` must be masked as `****-****-****-****` for the analyst role;
- `query_customer_transactions(rut)` must return only `UNIDAD_NEGOCIO = 'RETAIL'` rows for `FR_BI_ANALYST`;
- when the role is changed to `FR_DEMO_ADMIN`, the same query returns plaintext RUTs/PANs and the full customer set.

**Why filtering still works under masking:** Snowflake evaluates `WHERE`
predicates on the *post-policy* value, so a random mask would return 0 rows
for every analyst query. The policy is therefore *deterministic*
(`'***-**-' || right(sha2(val,256),12)`) and the MCP server recomputes the
same pseudonym client-side — the response's `rut_filter` field tells the
presenter which filter mode the role used (`deterministic pseudonym …` vs
`plaintext (admin policy bypass)`).

The return payload always echoes `role`, `warehouse`, `rut_filter` and a
`governance` note, so the presenter can show *who* answered, not just *what*.

## Related reading

- Session 1 (data foundation): `../session-1-lakehouse/README.md`
- Execution order & guardrails: `../../prompts/03-execution-validation.md`

