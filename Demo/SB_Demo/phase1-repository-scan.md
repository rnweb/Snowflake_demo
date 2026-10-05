# Phase 1 — Quickstart Repository Scan

**Status:** executed — regex/AST parsing over the 4 cloned Quickstarts.
**Source of truth:** clones in [`quickstarts/`](quickstarts/) (immutable, git-ignored).
**Naming authority:** [`naming-conventions.md`](naming-conventions.md) (approved, v2.0).

## Cloned Repositories

| # | Repository | Session |
|---|------------|---------|
| 1 | `sfguide-getting-started-dataengineering-ml-snowpark-python` | 1 — Lakehouse |
| 2 | `getting-started-with-dbt-on-snowflake` | 1 — dbt |
| 3 | `sfguide-build-chatbot-with-snowflake-native-app-snowflake-cortex` | 2 — Cortex |
| 4 | `sfguide-getting-started-with-horizon-data-governance-in-snowflake` | 3 — Governance |

## Scan Result: Generic Token Matches

Searched all `.sql` / `.py` / `.yml` files for the approved generic source names
(`QUICKSTART_DB`, `DEMO_DB`, `RETAIL_SCHEMA`, `ANALYTICS_SCHEMA`, `CUSTOMER_TABLE`,
`ORDERS_TABLE`, `DATA_ENGINEER_ROLE`, `ANALYST_ROLE`, `COMPUTE_WH`, `ANALYTICS_WH`):
**0 hits.** The approved table is an abstraction layer — the mapping below translates
each repository's *actual* hardcoded names into the approved banking targets.

## Object Inventory → Banking Mapping

### 1. dataengineering-ml-snowpark (Session 1)

| File | Hardcoded Object | Banking Target |
|------|------------------|----------------|
| `setup.sql:4` | `WAREHOUSE DASH_S` | `WH_INGESTION_XSMALL` |
| `setup.sql:5` | `DATABASE DASH_DB` | `SUPERINTENDENCY_DEMO_DB` |
| `setup.sql:6` | `SCHEMA DASH_SCHEMA` | `CORE_BANKING_SCHEMA` |
| `automate_data_pipeline_ml.py:150,160` | `WAREHOUSE = 'DASH_L'` | `WH_INGESTION_XSMALL` |
| Streamlit `*.py` | `DASH_DB` refs | `SUPERINTENDENCY_DEMO_DB` |

### 2. dbt-on-snowflake (Session 1)

| File | Hardcoded Object | Banking Target |
|------|------------------|----------------|
| `profiles.yml` (dev/prod) | `database: tasty_bytes_dbt_db` | `SUPERINTENDENCY_DEMO_DB` |
| `profiles.yml` (dev/prod) | `schema: dev` / `prod` | `STAGING_SCHEMA` / `RISK_ANALYTICS_SCHEMA` |
| `profiles.yml` (dev/prod) | `warehouse: tasty_bytes_dbt_wh` | `WH_INGESTION_XSMALL` |
| `profiles.yml` (dev/prod) | `role: accountadmin` | `FR_DATA_ENGINEER` — **guardrail fix: agent must not run dbt as ACCOUNTADMIN** |
| `setup/tasty_bytes_setup.sql:43-49` | `tasty_bytes_dbt_db` + `dev/prod/raw/integrations` schemas | `SUPERINTENDENCY_DEMO_DB` + `STAGING_SCHEMA`/`RISK_ANALYTICS_SCHEMA`/`CORE_BANKING_SCHEMA` |
| `models/marts/orders.sql` | `ORDERS` fact | `CREDIT_CARD_TRANSACTIONS` |
| `models/marts/customer_loyalty_metrics.sql` | customer metrics | `CLIENT_PROFILE_DIM`-based metrics |

### 3. cortex-native-app-chatbot (Session 2)

| File | Hardcoded Object | Banking Target |
|------|------------------|----------------|
| `scripts/lab_setup.sql:3` | `ROLE nactx_role` | `FR_DATA_ENGINEER` |
| `scripts/lab_setup.sql:19` | `ROLE nac` | `FR_BI_ANALYST` (app consumer sees masked data) |
| `scripts/lab_setup.sql:15` | `WAREHOUSE wh_nap` (app processing) | `WH_CORTEX_LARGE` |
| `scripts/lab_setup.sql:28` | `WAREHOUSE wh_nac` (app UI) | `WH_APP_XSMALL` *(approved)* |
| `scripts/lab_setup.sql:12-13` | `DATABASE cortex_app` / `SCHEMA cortex_app.napp` | Native App package → **`CORTEX_NATIVE_APP_DB`** *(approved — separate database, `terraform/main.tf`)* |
| `scripts/lab_setup.sql:29-30` | `DATABASE movies` / `SCHEMA movies.data` | `SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA` (raw docs) |
| `app/setup_script.sql` | `movies_metadata_chunked` | → `RISK_ANALYTICS_SCHEMA` (doc chunks for embeddings) |

### 4. horizon-data-governance (Session 3)

| File | Hardcoded Object | Banking Target |
|------|------------------|----------------|
| `0-lab-Setup.sql:54` | `DATABASE HRZN_DB` | `SUPERINTENDENCY_DEMO_DB` |
| `0-lab-Setup.sql:55` | `SCHEMA HRZN_DB.HRZN_SCH` | `CORE_BANKING_SCHEMA` |
| `0-lab-Setup.sql:43` | `WAREHOUSE HRZN_WH` | `WH_CORTEX_LARGE` |
| `0-lab-Setup.sql:24` | `ROLE HRZN_DATA_ENGINEER` | `FR_DATA_ENGINEER` |
| `0-lab-Setup.sql:26` | `ROLE HRZN_DATA_USER` | `FR_BI_ANALYST` (masked test role) |
| `0-lab-Setup.sql:25` | `ROLE HRZN_DATA_GOVERNOR` | `FR_DEMO_ADMIN` *(approved)* |
| `0-lab-Setup.sql:27` | `ROLE HRZN_IT_ADMIN` | `FR_DEMO_ADMIN` — consolidated (approved) |
| `hol-lab/1-DataEngineer.sql:129` | `ROLE HRZN_DATA_ANALYST` | `FR_BI_ANALYST` |
| `0-lab-Setup.sql:81,85,98` | `CLASSIFIERS`, `TAG_SCHEMA`, `SEC_POLICIES_SCHEMA` | `GOVERNANCE_SCHEMA` *(approved — consolidated 3 → 1)* |
| `1-DataEngineer.sql` | table `CUSTOMER` | `CLIENT_PROFILE_DIM` — **DDM target (SSN/National ID)** |
| `1-DataEngineer.sql` | table `CUSTOMER_ORDERS` | `CREDIT_CARD_TRANSACTIONS` |

## Findings for Phase 2

> **Phase 2 status:** all decisions below are **APPROVED** — see
> [naming-conventions.md](naming-conventions.md). Infrastructure is provisioned with
> Terraform (`../terraform/`); refactored scripts hold data & logic only.

1. **Zero literal matches** for approved generic tokens → Phase 2 must translate
   *actual* repo names using this report, not regex on the generic list.
2. **`role: accountadmin` in `profiles.yml`** violates the security guardrail —
   **APPROVED fix applied**: `dbt/profiles.yml` hardcodes
   `role: FR_DATA_ENGINEER`.
3. **3 governance schemas → 1** — **APPROVED**: consolidated into `GOVERNANCE_SCHEMA`.
4. **Native App package database** (`cortex_app`) cannot live inside
   `SUPERINTENDENCY_DEMO_DB` — **APPROVED**: separate database `CORTEX_NATIVE_APP_DB`
   (provisioned in `terraform/main.tf`).
5. All original clones remain untouched; refactored copies go to `scripts/`.
