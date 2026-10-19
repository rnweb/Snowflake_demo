# Asset Inventory — Snowflake Platform Demo

Master catalogue of **every object provisioned by the demo automation** across the
three sessions (infrastructure, data, AI and governance). Infrastructure is
Terraform-managed (`terraform/`); data and logic live
under `scripts/` and `dbt/`.

Snapshot verified against the live account on **2026-09-29**, re-verified on
**2026-10-07** after the security hardening and on **2026-10-15** after the
third-party audit fixes below (`SHOW` commands and `COUNT(*)` per table — see
[Verification](#verification)).

## Naming: raw tables vs dbt models

| Confusion | Reality |
|-----------|---------|
| Raw source tables are **Spanish, UPPERCASE**: `STAGING_SCHEMA.CLIENTES`, `TARJETAS_CREDITO`, `TRANSACCIONES` | Created by Session 1 (`sql/01_create_raw_tables.sql`) in the raw landing schema |
| dbt models are **lowercase in the project**: `stg_clientes`, `client_profile_dim`, `credit_card_transactions` | Snowflake stores unquoted identifiers uppercase — `CLIENT_PROFILE_DIM` and `credit_card_transactions` in the warehouse |
| Which schema holds what? | `STAGING_SCHEMA` = raw tables **+** dbt staging views (`STG_*`); `CORE_BANKING_SCHEMA` = dbt marts (`CLIENT_PROFILE_DIM`, `CREDIT_CARD_TRANSACTIONS`); `RISK_ANALYTICS_SCHEMA` = model workbench; `GOVERNANCE_SCHEMA` = policies and role mapping |

---

## 1. Infrastructure

**Source of truth:** `terraform/` (`main.tf`, `security.tf`, `governance.tf`,
`providers.tf`). Provider: `snowflakedb/snowflake ~> 2.21.0`.

### Databases and schemas

| Object | Provisioned by | Purpose |
|--------|----------------|---------|
| `SUPERINTENDENCY_DEMO_DB` | `main.tf` | Demo database (all data/AI/governance objects) |
| `├── STAGING_SCHEMA` | `main.tf` | **Bronze** — raw ingestion layer and Iceberg external tables: Spanish landing tables + dbt staging views + file format/stages |
| `├── CORE_BANKING_SCHEMA` | `main.tf` | **Silver/Gold** — curated dbt models, aggregated entities, and governed data (marts + Iceberg lakehouse table) |
| `├── RISK_ANALYTICS_SCHEMA` | `main.tf` | Data Science workspaces and Snowpark ML models (Model Registry: `DETECTOR_FRAUDES`) |
| `├── GOVERNANCE_SCHEMA` | `main.tf` | Masking/RLS policies, tag, `ROLE_MAPPING` |
| `├── CORTEX_VECTOR_STORE` | `main.tf` | Vector embeddings and document chunks for Cortex RAG retrieval |
| `CORTEX_NATIVE_APP_DB` | `main.tf` | Native App / Streamlit staging area |
| `└── PUBLIC` | built-in | `STREAMLIT_STAGE` (app source files) |

### Warehouses

| Warehouse | Size | Auto-suspend | Purpose |
|-----------|------|--------------|---------|
| `WH_INGESTION_XSMALL` | XSMALL | 60 s | Snowpipe / dbt runs |
| `WH_CORTEX_LARGE` | LARGE | 120 s | Optional heavy benches only — **no script defaults here** (trial-credit guardrail); runtimes accept `SNOWFLAKE_WAREHOUSE` |
| `WH_APP_XSMALL` | XSMALL | 60 s | Default compute: Streamlit / Native App, ML training, Cortex SQL, MCP sessions |

All created `INITIALLY SUSPENDED`; timeouts 300 s (ingestion/app), 600 s (Cortex).

### Roles and hierarchy

```
OPERATIONS (key-pair user)
└── FR_DEMO_ADMIN            # hierarchy root — orchestrates, bypasses policies
    ├── FR_DATA_ENGINEER     # builds: dbt, Snowpipe, Snowpark, vector store, app deploy
    └── FR_BI_ANALYST        # reads: masked PII, RLS-filtered rows, document vectors
FR_TERRAFORM                 # separate IaC-only role (no demo-hierarchy grants)
```

- **Terraform-managed grants** (`security.tf`): engineer build privileges on
  staging/core/analytics/vector-store (incl. `CREATE ICEBERG TABLE`, `CREATE MODEL`),
  analyst read-only `SELECT` on core/analytics/vector-store plus `USAGE` on
  `CORTEX_NATIVE_APP_DB` — **no staging access** (revoked 2026-10-07) —, warehouse `USAGE`,
  admin policy authoring (`CREATE MASKING POLICY`/`ROW ACCESS POLICY`/`TAG` on
  `GOVERNANCE_SCHEMA`), `MODIFY` + `SELECT` on core, DML on governance tables.
- **Manual bootstrap (not in Terraform, documented in `phase3-next-steps.md`):**
  `ACCOUNTADMIN` granted `APPLY MASKING POLICY` + `APPLY ROW ACCESS POLICY`
  (account-level only) to `FR_DEMO_ADMIN`; `FR_TERRAFORM` gets its base grants
  the same way. Policy **attachment** runs through the aliased
  `snowflake.policy_author` provider (runs as `FR_DEMO_ADMIN`).
- No demo role receives `ACCOUNTADMIN`.

### Stages and file formats

| Object | Location | Created by | Purpose |
|--------|----------|------------|---------|
| `RAW_STAGE` | `STAGING_SCHEMA` | Session 1 SQL | Raw CSV landing |
| `RAW_CSV_FORMAT` (CSV) | `STAGING_SCHEMA` | Session 1 SQL | CSV parsing (`SKIP_HEADER=1`) |
| `ICEBERG_DEMO_STAGE` | `STAGING_SCHEMA` | Session 1 `03_iceberg…` | Parquet source for the Iceberg table |
| `STREAMLIT_STAGE` | `CORTEX_NATIVE_APP_DB.PUBLIC` | `main.tf` | App source files (deployed via `session-2/sql/04_deploy_streamlit.sql`, human-gated) |

---

## 2. Data assets — staging (raw + lakehouse)

| Object (exact name) | Type | Rows | Created by |
|---------------------|------|------|------------|
| `SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.CLIENTES` | table | 600 | Session 1 + synthetic loader |
| `…STAGING_SCHEMA.TARJETAS_CREDITO` | table | 928 | Session 1 + synthetic loader |
| `…STAGING_SCHEMA.TRANSACCIONES` | table | 18 000 | Session 1 + synthetic loader |
| `…STAGING_SCHEMA.STG_CLIENTES` | view | — | dbt (`staging/stg_clientes.sql`) |
| `…STAGING_SCHEMA.STG_TARJETAS_CREDITO` | view | — | dbt (`staging/stg_tarjetas_credito.sql`) |
| `…STAGING_SCHEMA.STG_TRANSACCIONES` | view | — | dbt (`staging/stg_transacciones.sql`) |
| `…CORE_BANKING_SCHEMA.HISTORICO_TRANSACCIONES_ICEBERG` | **Iceberg table** | 18 000 | Session 1 `03_iceberg_lakehouse_demo.sql` |

- Iceberg table: **open-format, Snowflake-managed** (`CATALOG='SNOWFLAKE'` —
  Iceberg spec files on Snowflake storage, loaded from Parquet on
  `ICEBERG_DEMO_STAGE`, 3 files, 518 744 bytes); row parity with the raw mart
  verified (`is_iceberg='Y'`). Reading it from *external* engines would need an
  **External Volume** (cloud-storage credentials) — a documented future
  extension, not provisioned in this demo.
- No masking or RLS policies are attached to this layer — and since the
  2026-10-07 hardening `FR_BI_ANALYST` has **no access here at all**
  ([scope notes](#scope-notes)); raw tables are reachable by
  `FR_DEMO_ADMIN`/`FR_DATA_ENGINEER` only.

---

## 3. Data assets — core (dbt marts + policy data)

| Object (exact name) | Type | Rows | Created by | Governance |
|---------------------|------|------|------------|------------|
| `…CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM` | table (dbt `client_profile_dim`) | 600 | `dbt build` | `RUT` → `MASK_NATIONAL_ID` |
| `…CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS` | incremental (dbt `credit_card_transactions`) | 18 000 | `dbt build` | `RUT` → `MASK_NATIONAL_ID` (deterministic); `NUMERO_TARJETA` → `MASK_CREDIT_CARD`; `UNIDAD_NEGOCIO` → `RLS_BUSINESS_UNIT` |
| `…GOVERNANCE_SCHEMA.ROLE_MAPPING` | table | 4 | `governance.tf` DDL + Session 3 seed | RLS lookup: role → business unit |
| `…CORTEX_VECTOR_STORE.DOCUMENTS` | table | demo set | Session 2 SQL | embeddings and vector search context |

Mart facts: `UNIDAD_NEGOCIO` = PYME 6 223 / CORPORATIVO 5 928 / RETAIL 5 849;
`ESTADO` = APROBADA 15 282 / RECHAZADA 1 851 / PENDIENTE 867.

---

## 4. Analytics & AI

| Asset | Detail |
|-------|--------|
| **Model** `SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES` (V1) | RandomForest fraud detector, trained by `session-2/python/01_train_fraud_model.py` on the mart; features `MONTO`, `HORA`, `DIA_SEMANA`, `FIN_DE_SEMANA`, `CATEGORIA_ALTO_RIESGO`, `UNIDAD_NEGOCIO_COD`; evaluation: `EVALUADOS=3651 ACCURACY=0.9310 RECALL=0.4404 PRECISION=0.7608` |
| **Cortex AI** (5 blocks, `session-2/sql/02_cortex_ai_features.sql`) | `SNOWFLAKE.CORTEX.SUMMARIZE`, `SNOWFLAKE.CORTEX.TRANSLATE`, `SNOWFLAKE.CORTEX.COMPLETE` ×2, and the `CORTEX_VECTOR_STORE` retrieval block for RAG context |
| **Streamlit** `PANEL_PREVENCION_FRAUDE` | Source: `session-2/streamlit_app.py` (Spanish UI: KPIs, charts, model-inference form, Cortex text box). **Deployed 2026-10-15** via `session-2/sql/04_deploy_streamlit.sql` after explicit human approval |
| **MCP server** (C06-PRE-06 & C06-AE-08) | `session-2/python/mcp_server.py` — stdio Model Context Protocol server exposing `query_customer_transactions(rut)` over `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS` with masking + RLS in Snowflake |

---

## 5. Governance

### Policies and tags (`governance.tf`, owned by `FR_DEMO_ADMIN`)

| Object | Type | Attached to | Effect |
|--------|------|-------------|--------|
| `MASK_NATIONAL_ID` | masking policy | `CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM.RUT` + `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.RUT` (2 applications) | deterministic `***-**-<12 hex>` pseudonym for non-admin roles |
| `MASK_CREDIT_CARD` | masking policy | `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA` | `****-****-****-****` for non-admin roles |
| `RLS_BUSINESS_UNIT` | row-access policy | `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.UNIDAD_NEGOCIO` | Row filter via `GOVERNANCE_SCHEMA.ROLE_MAPPING` (bound by Session 3 SQL — one-shot attachment to the mart) |
| `DATA_CLASSIFICATION` | tag | `CLIENT_PROFILE_DIM.RUT`, `CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA` (domain `COLUMN`) | Horizon label `= 'PII'` (set by Session 3 `03_object_tagging_demo.sql`) |

Attachment switch: `terraform/terraform.tfvars` → `attach_policies_to_tables = true`
(**3 column-policy applications** via `snowflake.policy_author`:
`dim.RUT`, `fact.RUT`, `fact.NUMERO_TARJETA`).

### Verified access matrix

| Persona | PII (`RUT` / `NUMERO_TARJETA`) | Transaction rows | Build objects |
|---------|-------------------------------|------------------|---------------|
| `FR_DEMO_ADMIN` / `ACCOUNTADMIN` | plaintext (policy bypass) | 18 000 (PYME+CORPORATIVO+RETAIL) | yes |
| `FR_DATA_ENGINEER` | pseudonym `***-**-<12 hex>` / masked `****-****-****-****` | 18 000 (all units — dbt/ML keep working) | yes |
| `FR_BI_ANALYST` | pseudonym `***-**-<12 hex>` / masked `****-****-****-****` | 5 849 (RETAIL only) | no (read-only) |

Policy subqueries run with the policy owner's privileges, so `FR_BI_ANALYST`
needs **no** governance grants of its own.

### Scope notes

- **Gap closed (2026-10-07).** Raw tables (`STAGING_SCHEMA.CLIENTES.RUT`, …)
  carry no masking policies, and `FR_BI_ANALYST` used to hold `SELECT` there —
  which would have bypassed the Dynamic Data Masking narrative. Terraform
  (`security.tf`) now **revokes** the analyst's `USAGE`/`SELECT` on
  `STAGING_SCHEMA` (resources `analyst_staging_read`,
  `analyst_staging_select_all`, `analyst_staging_select_future` removed);
  verified live: `SHOW GRANTS TO ROLE FR_BI_ANALYST` returns **no STAGING
  entries**. The analyst reads `CORE_BANKING_SCHEMA`, `RISK_ANALYTICS_SCHEMA`,
  `CORTEX_VECTOR_STORE`, and `CORTEX_NATIVE_APP_DB` only; masking stays attached to the two core-mart
  columns.
- **Session isolation (2026-10-07).** The revocation alone was not enough: the
  operator user `OPERATIONS` also holds `FR_DEMO_ADMIN`/`FR_TERRAFORM`, and
  Snowflake activates every role of a user as a *secondary* role by default —
  so an `FR_BI_ANALYST` session still inherited `FR_DATA_ENGINEER`'s staging
  privileges through the hierarchy. Persona sessions now run
  `USE SECONDARY ROLES NONE` (`scripts/session-3-governance/sql/02_verify_masking_rls.sql`,
  `scripts/session-2-analytics-ai/python/mcp_server.py`); verified live:
  `SELECT COUNT(*) …STAGING_SCHEMA.CLIENTES` **fails with `002003`** for the
  isolated analyst session while the core mart stays readable (5 849 RETAIL
  rows).
- **Fact-table RUT masked (2026-10-15 audit).** `CREDIT_CARD_TRANSACTIONS.RUT`
  previously exposed plaintext PII while the dim column was masked (same
  audit issue as the raw-layer gap). The column is now attached to
  `MASK_NATIONAL_ID`, and the policy body was changed from a constant
  `***-**-****` to a **deterministic** token: Snowflake applies `WHERE` to the
  *post-policy* value, so a constant mask broke every analyst filter
  (plaintext `WHERE RUT='5.017.491-3'` → 0 rows) while the token form
  (`WHERE RUT='***-**-e93d5c93280b'` → 76 rows) keeps queries working.
  `mcp_server.py` mirrors the policy (`sha256(rut)[-12:]`) so non-admin MCP
  sessions filter by the pseudonym and admins by plaintext — verified live
  for both personas (2026-10-15).
- **MCP pseudonymized filter (hash-based).** The agent never sees the plaintext
  `RUT` for restricted roles. The server computes a stable hash for the
  customer identifier and Snowflake applies the same deterministic token to the
  row policy, which keeps the analyst query working while the visible dataset is
  restricted to `UNIDAD_NEGOCIO = 'RETAIL'`.
- Schema `COMMENT`s follow the Medallion wording in `terraform/main.tf`
  (Bronze / Silver-Gold / Data Science) and were applied to the live schemas
  on 2026-10-07.

## Verification

Run as `FR_DEMO_ADMIN` on `WH_APP_XSMALL`:

```sql
SHOW TERSE TABLES IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW MASKING POLICIES IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW ROW ACCESS POLICIES IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW TAGS IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW MODELS IN SCHEMA SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA;
SHOW STREAMLITS IN DATABASE CORTEX_NATIVE_APP_DB;  -- PANEL_PREVENCION_FRAUDE (deployed)
SHOW GRANTS TO ROLE FR_BI_ANALYST;  -- must contain no STAGING_SCHEMA entries
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES;      -- 18000
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM; -- 600
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS;    -- demo rows available
```

Persona isolation check (as `FR_BI_ANALYST`):

```sql
USE SECONDARY ROLES NONE;                                                  -- see scope notes
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.CLIENTES;      -- must FAIL: 002003
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORTEX_VECTOR_STORE.DOCUMENTS; -- should succeed (read-only schema access)
```

Persona proofs live in `scripts/session-3-governance/sql/02_verify_masking_rls.sql`.

## Related documentation

- Demo overview & workflow: [`README.md`](README.md)
- Architecture & guardrails: [RF_IT docs](https://github.com/rnweb/RF_IT_Solutions/blob/main/docs/snowflake-platform-demo/architecture.md)
- Session 3 (presenter guide): [`scripts/session-3-governance/README.md`](scripts/session-3-governance/README.md)

