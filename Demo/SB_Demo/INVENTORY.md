# Asset Inventory — Snowflake Platform Demo

Master catalogue of **every object provisioned by the demo automation** across the
three sessions (infrastructure, data, AI and governance). Infrastructure is
Terraform-managed (`terraform/`); data and logic live
under `scripts/` and `dbt/`.

Snapshot verified against the live account on **2026-09-29** (`SHOW` commands and
`COUNT(*)` per table — see [Verification](#verification)).

## Naming: raw tables vs dbt models

| Confusion | Reality |
|-----------|---------|
| Raw source tables are **Spanish, UPPERCASE**: `STAGING_SCHEMA.CLIENTES`, `TARJETAS_CREDITO`, `TRANSACCIONES` | Created by Session 1 (`sql/01_create_raw_tables.sql`) in the raw landing schema |
| dbt models are **lowercase in the project**: `stg_clientes`, `client_profile_dim`, `credit_card_transactions` | Snowflake stores unquoted identifiers uppercase — `CLIENT_PROFILE_DIM` and `client_profile_dim` are the **same object** |
| Which schema holds what? | `STAGING_SCHEMA` = raw tables **+** dbt staging views (`STG_*`); `CORE_BANKING_SCHEMA` = dbt marts (`CLIENT_PROFILE_DIM`, `CREDIT_CARD_TRANSACTIONS`); `RISK_ANALYTICS_SCHEMA` = ML; `GOVERNANCE_SCHEMA` = policies + mapping table |

---

## 1. Infrastructure

**Source of truth:** `terraform/` (`main.tf`, `security.tf`, `governance.tf`,
`providers.tf`). Provider: `snowflakedb/snowflake ~> 2.21.0`.

### Databases and schemas

| Object | Provisioned by | Purpose |
|--------|----------------|---------|
| `SUPERINTENDENCY_DEMO_DB` | `main.tf` | Demo database (all data/AI/governance objects) |
| `├── STAGING_SCHEMA` | `main.tf` | Raw Spanish landing tables + dbt staging views + file format/stages |
| `├── CORE_BANKING_SCHEMA` | `main.tf` | dbt marts + Iceberg lakehouse table |
| `├── RISK_ANALYTICS_SCHEMA` | `main.tf` | Snowflake Model Registry (`DETECTOR_FRAUDES`) |
| `├── GOVERNANCE_SCHEMA` | `main.tf` | Masking/RLS policies, tag, `ROLE_MAPPING` |
| `CORTEX_NATIVE_APP_DB` | `main.tf` | Native App / Streamlit staging area |
| `└── PUBLIC` | built-in | `STREAMLIT_STAGE` (app source files) |

### Warehouses

| Warehouse | Size | Auto-suspend | Purpose |
|-----------|------|--------------|---------|
| `WH_INGESTION_XSMALL` | XSMALL | 60 s | Snowpipe / dbt runs |
| `WH_CORTEX_LARGE` | LARGE | 120 s | ML training + Cortex LLM queries |
| `WH_APP_XSMALL` | XSMALL | 60 s | Streamlit / Native App compute |

All created `INITIALLY SUSPENDED`; timeouts 300 s (ingestion/app), 600 s (Cortex).

### Roles and hierarchy

```
OPERATIONS (key-pair user)
└── FR_DEMO_ADMIN            # hierarchy root — orchestrates, bypasses policies
    ├── FR_DATA_ENGINEER     # builds: dbt, Snowpipe, Snowpark, ML, app deploy
    └── FR_BI_ANALYST        # reads: masked PII, RLS-filtered rows
FR_TERRAFORM                 # separate IaC-only role (no demo-hierarchy grants)
```

- **Terraform-managed grants** (`security.tf`): engineer build privileges on
  staging/core/analytics (incl. `CREATE ICEBERG TABLE`, `CREATE MODEL`),
  analyst read-only `SELECT` on staging/core/analytics, warehouse `USAGE`,
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
| `STREAMLIT_STAGE` | `CORTEX_NATIVE_APP_DB.PUBLIC` | `main.tf` | Holds `streamlit_app.py` until manual deploy |

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

- Iceberg table: managed Snowflake storage (`CATALOG='SNOWFLAKE'`), loaded from
  Parquet on `ICEBERG_DEMO_STAGE` (3 files, 518 744 bytes); row parity with the
  raw mart verified (`is_iceberg='Y'`).
- No masking or RLS policies are attached to this layer (see
  [scope note](#scope-notes)).

---

## 3. Data assets — core (dbt marts + policy data)

| Object (exact name) | Type | Rows | Created by | Governance |
|---------------------|------|------|------------|------------|
| `…CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM` | table (dbt `client_profile_dim`) | 600 | `dbt build` | `RUT` → `MASK_NATIONAL_ID` |
| `…CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS` | incremental (dbt `credit_card_transactions`) | 18 000 | `dbt build` | `NUMERO_TARJETA` → `MASK_CREDIT_CARD`; `UNIDAD_NEGOCIO` → `RLS_BUSINESS_UNIT` |
| `…GOVERNANCE_SCHEMA.ROLE_MAPPING` | table | 4 | `governance.tf` DDL + Session 3 seed | RLS lookup: role → business unit |

Mart facts: `UNIDAD_NEGOCIO` = PYME 6 223 / CORPORATIVO 5 928 / RETAIL 5 849;
`ESTADO` = APROBADA 15 282 / RECHAZADA 1 851 / PENDIENTE 867.

---

## 4. Analytics & AI

| Asset | Detail |
|-------|--------|
| **Model** `SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA.DETECTOR_FRAUDES` (V1) | RandomForest fraud detector, trained by `session-2/python/01_train_fraud_model.py` on the mart; features `MONTO, HORA, DIA_SEMANA, FIN_DE_SEMANA, CATEGORIA_ALTO_RIESGO, UNIDAD_NEGOCIO_COD`; ACCURACY 0.931 / RECALL 0.440 / PRECISION 0.761; callable from SQL via `MODEL(…DETECTOR_FRAUDES, V1)!predict(…)` |
| **Cortex AI** (4 statements, `session-2/sql/02_cortex_ai_features.sql`) | `SNOWFLAKE.CORTEX.SUMMARIZE`, `SNOWFLAKE.CORTEX.TRANSLATE`, `SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', …)`, `SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b', …)` — Spanish prompts. **Trial account gate `399258`**: statements compile and resolve but return "not available for trial accounts" until run on a standard account |
| **Streamlit** `PANEL_PREVENCION_FRAUDE` | Source: `session-2/streamlit_app.py` (Spanish UI: KPIs, charts, model-inference form, Cortex text box). Stage `STREAMLIT_STAGE` is provisioned; **the app is intentionally not deployed by automation** (human-approved manual `CREATE STREAMLIT` — currently not deployed) |

---

## 5. Governance

### Policies and tags (`governance.tf`, owned by `FR_DEMO_ADMIN`)

| Object | Type | Attached to | Effect |
|--------|------|-------------|--------|
| `MASK_NATIONAL_ID` | masking policy | `CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM.RUT` | `***-**-****` for non-admin roles |
| `MASK_CREDIT_CARD` | masking policy | `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA` | `****-****-****-****` for non-admin roles |
| `RLS_BUSINESS_UNIT` | row-access policy | `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.UNIDAD_NEGOCIO` | Row filter via `GOVERNANCE_SCHEMA.ROLE_MAPPING` (bound by Session 3 SQL — one-shot `ALTER TABLE`) |
| `DATA_CLASSIFICATION` | tag | `CLIENT_PROFILE_DIM.RUT`, `CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA` (domain `COLUMN`) | Horizon label `= 'PII'` (set by Session 3 `03_object_tagging_demo.sql`) |

Attachment switch: `terraform/terraform.tfvars` → `attach_policies_to_tables = true`
(both masking policies are attached via `snowflake.policy_author`).

### Verified access matrix

| Persona | PII (`RUT` / `NUMERO_TARJETA`) | Transaction rows | Build objects |
|---------|-------------------------------|------------------|---------------|
| `FR_DEMO_ADMIN` / `ACCOUNTADMIN` | plaintext (policy bypass) | 18 000 (PYME+CORPORATIVO+RETAIL) | yes |
| `FR_DATA_ENGINEER` | masked | 18 000 (all units — dbt/ML keep working) | yes |
| `FR_BI_ANALYST` | masked | 5 849 (RETAIL only) | no (read-only) |

Policy subqueries run with the policy owner's privileges, so `FR_BI_ANALYST`
needs **no** governance grants of its own.

### Scope notes

- Masking is attached to the **two core-mart columns only**. Raw tables
  (`STAGING_SCHEMA.CLIENTES.RUT`, …) carry no policies; `FR_BI_ANALYST` holds
  `SELECT` there for lineage demos and would see raw values. If a stricter
  story is needed for the presentation, attach the same policies to the raw
  columns (or revoke analyst staging `SELECT`).
- `terraform/main.tf` schema *comments* predate the final layer split (the
  `CORE_BANKING_SCHEMA` comment still says "Raw ingestion layer"); object
  placement in this inventory reflects the verified live state.

## Verification

Run as `FR_DEMO_ADMIN` on `WH_APP_XSMALL`:

```sql
SHOW TERSE TABLES IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW MASKING POLICIES IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW ROW ACCESS POLICIES IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW TAGS IN DATABASE SUPERINTENDENCY_DEMO_DB;
SHOW MODELS IN SCHEMA SUPERINTENDENCY_DEMO_DB.RISK_ANALYTICS_SCHEMA;
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES;      -- 18000
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM; -- 600
```

Persona proofs live in `scripts/session-3-governance/sql/02_verify_masking_rls.sql`.

## Related documentation

- Demo overview & workflow: [`README.md`](README.md)
- Architecture & guardrails: [RF_IT docs](https://github.com/rnweb/RF_IT_Solutions/blob/main/docs/snowflake-platform-demo/architecture.md)
- Session 3 (presenter guide): [`scripts/session-3-governance/README.md`](scripts/session-3-governance/README.md)
