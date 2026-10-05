# Naming Conventions — Banking Persona Mapping

**Status: APPROVED (v2.0)** — single source of truth for object naming.
All infrastructure names are provisioned as Terraform variables
([`terraform/variables.tf`](terraform/variables.tf) + [`terraform/terraform.tfvars`](terraform/terraform.tfvars)).
Originals in `quickstarts/` stay untouched (cloned repos are immutable source of truth;
refactored copies live in `scripts/`).

## Approved Mapping

| Generic Quickstart Object | Banking Demo Target | Purpose / Justification |
| :--- | :--- | :--- |
| `QUICKSTART_DB` / `DEMO_DB` | `SUPERINTENDENCY_DEMO_DB` | Primary database housing all session assets. |
| `RETAIL_SCHEMA` / `SALES` | `CORE_BANKING_SCHEMA` | Raw ingestion layer for transactional data. |
| `ANALYTICS_SCHEMA` | `RISK_ANALYTICS_SCHEMA` | Transformed layer for BI, RLS, and Cortex. |
| `CUSTOMER_TABLE` | `CLIENT_PROFILE_DIM` | Target for Dynamic Data Masking (SSN/National ID). |
| `ORDERS_TABLE` | `CREDIT_CARD_TRANSACTIONS` | High-volume transactional fact table. |
| `DATA_ENGINEER_ROLE` | `FR_DATA_ENGINEER` | Functional role mapping for pipeline creation. |
| `ANALYST_ROLE` | `FR_BI_ANALYST` | Functional role to test masking policies (masked view). |
| `COMPUTE_WH` | `WH_INGESTION_XSMALL` | Compute dedicated to Snowpipe and dbt runs. |
| `ANALYTICS_WH` | `WH_CORTEX_LARGE` | Compute allocated for ML and Cortex LLM queries. |

## Derived Objects — APPROVED (v2.0)

| Generic / Need | Approved Target | Purpose / Justification |
| :--- | :--- | :--- |
| dbt intermediate layer | `STAGING_SCHEMA` | dbt requires a staging schema between raw and analytics. |
| Policies & mapping tables | `GOVERNANCE_SCHEMA` | Masking/row-access policies and role-mapping tables (Session 3). |
| Agent-scoped admin role | `FR_DEMO_ADMIN` | Scoped replacement for ACCOUNTADMIN per security guardrails. |
| Streamlit compute | `WH_APP_XSMALL` | Session 2 app compute, separated from WH_CORTEX_LARGE. |
| Native App package database | `CORTEX_NATIVE_APP_DB` | Native Apps require a separate application package database. |

## Phase 2 Decisions — APPROVED

- **dbt guardrail:** `profiles.yml` hardcodes `role: FR_DATA_ENGINEER`
  (never `ACCOUNTADMIN`) — see [`dbt/profiles.yml`](dbt/profiles.yml).
- **Governance consolidation:** the three Quickstart schemas
  (`CLASSIFIERS`, `TAG_SCHEMA`, `SEC_POLICIES_SCHEMA`) consolidate into the single
  `GOVERNANCE_SCHEMA`.
- **Roles:** `HRZN_IT_ADMIN` maps to `FR_DEMO_ADMIN` (consolidated with `HRZN_DATA_GOVERNOR`).
- **Native App:** `CORTEX_NATIVE_APP_DB` stays a separate database.

## Usage Rules

1. **Never** reference `QUICKSTART_*`, `DEMO_*`, `RETAIL_*`, `ANALYTICS_WH`, `HRZN_*`,
   `DASH_*`, `tasty_bytes_*`, etc. in project scripts.
2. Every infrastructure object name comes from
   [`terraform/variables.tf`](terraform/variables.tf), populated in
   [`terraform/terraform.tfvars`](terraform/terraform.tfvars) — change names there,
   nowhere else.
3. Functional roles use the `FR_` prefix; compute uses the `WH_` prefix; database and
   schema names are uppercase with underscores.
4. **Data & logic never live in Terraform** — tables' rows, dbt models, ML code and
   Streamlit apps belong in `scripts/session-*/`.
