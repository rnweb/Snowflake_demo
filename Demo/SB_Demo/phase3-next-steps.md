# Phase 3 — Next Steps: Data, Logic & App Delivery

> **Status:** Phase 2 (Terraform IaC) is **complete** — `terraform plan` reports
> *"No changes. Your infrastructure matches the configuration."* (55 resources).

Phase 3 delivers everything Terraform deliberately does **not** manage: data,
transformation logic and application code. Per the separation of concerns, these
live in `scripts/session-*` and are executed with the demo roles — never as
`FR_TERRAFORM` or `ACCOUNTADMIN`.

---

## 0. Already provisioned (Phase 2 output)

| Layer | Objects |
|---|---|
| Databases | `SUPERINTENDENCY_DEMO_DB`, `CORTEX_NATIVE_APP_DB` |
| Schemas | `CORE_BANKING_SCHEMA`, `STAGING_SCHEMA`, `RISK_ANALYTICS_SCHEMA`, `GOVERNANCE_SCHEMA` |
| Warehouses | `WH_INGESTION_XSMALL`, `WH_CORTEX_LARGE`, `WH_APP_XSMALL` |
| Roles | `FR_DEMO_ADMIN` → (`FR_DATA_ENGINEER`, `FR_BI_ANALYST`) |
| Governance | `MASK_NATIONAL_ID`, `MASK_CREDIT_CARD`, `RLS_BUSINESS_UNIT`, `ROLE_MAPPING` table (empty) |
| RBAC | 36 grant resources — 33 least-privilege grants + 3 role-hierarchy links (engineer builds, analyst reads, admin orchestrates) |

**Manual bootstrap (already executed as ACCOUNTADMIN — re-run only on a fresh account):**

```sql
-- Required because account-level grants cannot be issued by FR_TERRAFORM (003102)
GRANT APPLY MASKING POLICY  ON ACCOUNT TO ROLE FR_DEMO_ADMIN;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE FR_DEMO_ADMIN;
```

---

## 1. Session 1 — Data Foundation & dbt (`scripts/session-1-lakehouse/` + `dbt/`)

1. **Raw load (Spanish banking schema)** — from the repo root:

   ```bash
   python Demo/SB_Demo/scripts/session-1-lakehouse/python/generate_and_load.py
   ```

   Generates synthetic data (seed 42), creates `CLIENTES` /
   `TARJETAS_CREDITO` / `TRANSACCIONES` in `STAGING_SCHEMA`, PUT + `COPY INTO`
   as `FR_DATA_ENGINEER` on `WH_INGESTION_XSMALL` (600 / 928 / 18,000 rows).
2. **dbt** — `dbt/profiles.yml` pins `role: FR_DATA_ENGINEER`,
   `database: SUPERINTENDENCY_DEMO_DB`, `warehouse: WH_INGESTION_XSMALL`:

   ```bash
   cd Demo/SB_Demo/dbt
   dbt build --profiles-dir .             # staging views + marts + all tests
   dbt source freshness --profiles-dir .  # 3/3 sources fresh
   ```

   - Staging views in `STAGING_SCHEMA` (`stg_*`), marts in
     `CORE_BANKING_SCHEMA` (`CLIENT_PROFILE_DIM`, `CREDIT_CARD_TRANSACTIONS`)
   - Expected: `PASS=41 WARN=0 ERROR=0`
   - Full presenter runbook: `scripts/session-1-lakehouse/README.md`
3. **Quickstart reference:** `quickstarts/dbt-on-snowflake`.

## 2. Session 2 — Snowpark, Cortex & Streamlit (`scripts/session-2-analytics-ai/`)

1. **Snowpark ML** — `python/01_train_fraud_model.py` as `FR_DATA_ENGINEER` on
   `WH_CORTEX_LARGE`: feature SQL over the dbt mart, RandomForest training,
   evaluation and registration of `RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES`
   (V1), callable from SQL.
2. **Cortex AI (español)** — `sql/02_cortex_ai_features.sql`, four statements
   (`CORTEX.SUMMARIZE`, `CORTEX.TRANSLATE`, `CORTEX.COMPLETE` ×2) as
   `FR_DATA_ENGINEER` on `WH_CORTEX_LARGE`; trial accounts stop at the
   documented licence gate `399258`.
3. **MCP server — required for the evaluators** — initialize before the demo:

   ```bash
   python -m pip install mcp
   python Demo/SB_Demo/scripts/session-2-analytics-ai/python/mcp_server.py
   ```

   The stdio server exposes `query_customer_transactions(rut)` over the Model
   Context Protocol so an external AI client (e.g. Claude Desktop) queries the
   lakehouse through the governed role (`FR_BI_ANALYST` by default; every
   session runs `USE SECONDARY ROLES NONE`). **This step is required to
   demonstrate external AI integration and to verify the row-level security /
   dynamic data masking isolation for the evaluators**: masked card numbers,
   RETAIL-only rows, `002003` on the raw layer. Full setup and presenter demo
   script: `scripts/session-2-analytics-ai/README.md` (Step 4).
4. **Streamlit** — `streamlit_app.py` deploys to `CORTEX_NATIVE_APP_DB.PUBLIC`
   with `WH_APP_XSMALL`; run the `PUT` + `CREATE STREAMLIT` as
   `FR_DATA_ENGINEER` **only after explicit human approval** (never automated).
5. **Native App** — target database `CORTEX_NATIVE_APP_DB` (separate database
   on purpose; app installs are not Terraform-managed).
6. **Quickstarts:** `quickstarts/dataengineering-ml-snowpark`
   (`sfguide-getting-started-dataengineering-ml-snowpark-python`),
   `quickstarts/cortex-native-app-chatbot`
   (`sfguide-build-chatbot-with-snowflake-native-app-snowflake-cortex`).

## 3. Session 3 — Governance Activation (`scripts/session-3-governance/`)

Executed **after** `CLIENT_PROFILE_DIM` and `CREDIT_CARD_TRANSACTIONS` exist
(session 1 data). Three steps, two of them gated:

1. **Seed the mapping table** as `FR_DEMO_ADMIN`:
   `INSERT INTO GOVERNANCE_SCHEMA.ROLE_MAPPING ...` (Terraform creates the
   table; rows are data).
2. **Masking** — set `attach_policies_to_tables = true` in
   `terraform.tfvars`, then `terraform apply` (2 column-policy applications).
3. **Row-level security** — bind via SQL (no Terraform resource exists for it):

   ```sql
   ALTER TABLE SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS
     ADD ROW ACCESS POLICY SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.RLS_BUSINESS_UNIT
      ON (UNIDAD_NEGOCIO);
   ```

4. **Verify:** run `scripts/session-3-governance/sql/02_verify_masking_rls.sql`
   — every persona section starts with `USE SECONDARY ROLES NONE` so only the
   role under test is effective — and compare `FR_BI_ANALYST` (masked PII +
   filtered rows) vs `FR_DEMO_ADMIN` (plaintext). Quickstart:
   `quickstarts/horizon-data-governance`
   (`sfguide-getting-started-with-horizon-data-governance-in-snowflake`).

---

## Guardrails to keep in Phase 3

- **Roles:** dbt → `FR_DATA_ENGINEER` only (encoded in `profiles.yml`);
  data loads never run as `ACCOUNTADMIN`/`FR_TERRAFORM`.
- **IaC boundary:** databases / schemas / warehouses / roles / grants /
  policies → Terraform; tables' data, rows, dbt models, app code → scripts.
- **Drift check:** `terraform plan` must stay clean (`No changes`); any manual
  Snowflake DDL on managed objects shows up there.
- **Docs:** `python -m mkdocs build --strict` before pushing site changes.
