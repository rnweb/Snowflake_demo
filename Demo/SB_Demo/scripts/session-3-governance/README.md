# Session 3 — Governance & Security (Horizon)

**Audience:** Data Governors & Security — Superintendency of Banks.

Same tables, three personas, **zero application changes**: dynamic masking for
PII and row-level security by business unit, plus the Horizon object-tagging
complement — all discoverable in Snowsight.

| Persona (role) | `RUT` / `NUMERO_TARJETA` | Business units visible |
|----------------|--------------------------|------------------------|
| `FR_DEMO_ADMIN` / `ACCOUNTADMIN` | **plaintext** (policy bypass) | PYME + CORPORATIVO + RETAIL (18 000 rows) |
| `FR_DATA_ENGINEER` | masked `****-****-****-****` | all three — mapped to every unit (dbt/ML keep working) |
| `FR_BI_ANALYST` | masked `***-**-****` / `****-****-****-****` | **RETAIL only (5 849 rows)** |

## Objects in scope (exact names)

| Layer | Object | Role in this session |
|-------|--------|----------------------|
| Raw source | `SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.CLIENTES` | upstream client data — lineage starts here (no policies attached) |
| dbt staging view | `SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.STG_CLIENTES` | middle hop of the lineage chain |
| dbt mart | `SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM` | `RUT` column → `MASK_NATIONAL_ID` |
| dbt mart | `SUPERINTENDENCY_DEMO_DB.CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS` | `NUMERO_TARJETA` → `MASK_CREDIT_CARD`; `UNIDAD_NEGOCIO` → `RLS_BUSINESS_UNIT` |
| Policy data | `SUPERINTENDENCY_DEMO_DB.GOVERNANCE_SCHEMA.ROLE_MAPPING` | role → business-unit mapping consumed by the RLS policy |

> dbt model names are lowercase in the project (`client_profile_dim`,
> `credit_card_transactions`); Snowflake stores them uppercase
> (`CLIENT_PROFILE_DIM`, `CREDIT_CARD_TRANSACTIONS`) — same objects.

## Files

| File | Purpose |
|------|---------|
| `sql/01_seed_role_mapping.sql` | Seeds `GOVERNANCE_SCHEMA.ROLE_MAPPING` + binds the RLS policy (`ALTER TABLE ... ADD ROW ACCESS POLICY` — no Terraform resource exists) |
| `sql/02_verify_masking_rls.sql` | Admin-vs-analyst proof: plaintext/all-units vs masked/RETAIL-only |
| `sql/03_object_tagging_demo.sql` | Tags the PII columns with `DATA_CLASSIFICATION = 'PII'` (Horizon object tagging) |
| `../../terraform/governance.tf` | Masking + row-access policies, `ROLE_MAPPING` DDL, `attach_policies_to_tables` switch |

## Prerequisites

- Sessions 1–2 complete (mart tables + dbt run exist)
- `terraform/terraform.tfvars` → `attach_policies_to_tables = true`, then
  `terraform plan` (No changes) + `terraform apply` — attaches
  `MASK_NATIONAL_ID` → `CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM.RUT` and
  `MASK_CREDIT_CARD` → `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA`
- Environment: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` (key-pair),
  `SNOWFLAKE_PRIVATE_KEY_PATH`
- Role: `FR_DEMO_ADMIN` (granted to `OPERATIONS`), warehouse: `WH_APP_XSMALL`
  (the analyst has no `WH_INGESTION_XSMALL` grant)

## Step 1 — Seed + RLS binding

```bash
snowsql -f scripts/session-3-governance/sql/01_seed_role_mapping.sql
# ...or paste into a Snowsight worksheet
```

Expected output:

```
DELETE  -> 0 rows (first run)
INSERT  -> 4 rows
SELECT  -> FR_BI_ANALYST    | RETAIL
           FR_DATA_ENGINEER | CORPORATIVO
           FR_DATA_ENGINEER | PYME
           FR_DATA_ENGINEER | RETAIL
ALTER   -> Statement executed successfully.
```

The binding in step 3 is **one-shot**: re-running the file re-seeds cleanly,
but the final `ALTER` errors if the policy is already attached (ignore it).

## Step 2 — Verify masking + row-level security

```bash
snowsql -f scripts/session-3-governance/sql/02_verify_masking_rls.sql
```

Run the **whole file in one session** — it switches roles mid-way.

| Check | `FR_DEMO_ADMIN` | `FR_BI_ANALYST` |
|-------|-----------------|-----------------|
| `CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM.RUT` | `5.000.081-8` (plaintext) | `***-**-****` |
| `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA` | `3714-4911-9269-2129` | `****-****-****-****` |
| Rows per unit (`CREDIT_CARD_TRANSACTIONS`) | `CORPORATIVO 5928 / PYME 6223 / RETAIL 5849` (18 000) | `RETAIL 5849` only |
| `GOVERNANCE_SCHEMA.ROLE_MAPPING` | 4 rows visible | n/a |

## Step 3 — Horizon object tagging

```bash
snowsql -f scripts/session-3-governance/sql/03_object_tagging_demo.sql
```

Expected output:

```
CREATE TAG -> DATA_CLASSIFICATION already exists / created
SET TAG    -> Statement executed successfully.  (x2)
SELECT     -> CLIENT_PROFILE_DIM       | DATA_CLASSIFICATION | PII
              CREDIT_CARD_TRANSACTIONS | DATA_CLASSIFICATION | PII
```

No extra grants needed: `APPLY TAG` is account-level only (granting it on a
schema fails `003008`), and Snowflake lets any role holding `MODIFY` on the
table tag its columns — `FR_DEMO_ADMIN` got `MODIFY` on the core schema from
Terraform (`admin_core_modify`).

## Horizon walkthrough in Snowsight (presenter)

1. **Policies** — Data → `SUPERINTENDENCY_DEMO_DB` →
   `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS` → column details show the
   attached masking policy; the table's policy panel shows
   `RLS_BUSINESS_UNIT`. Cross-check the same facts via SQL:
   `SHOW MASKING POLICY ...`, `SHOW ROW ACCESS POLICY ...`.
2. **Object tagging** — the tagged PII columns (`CLIENT_PROFILE_DIM.RUT`,
   `CREDIT_CARD_TRANSACTIONS.NUMERO_TARJETA`) show
   `DATA_CLASSIFICATION = PII` on the column details and under the Data
   Governance Center → Object Tagging. This is the Horizon label that drives
   classification/discovery; the masking policies are the enforcement.
3. **Lineage** — Data → browse to
   `SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.TRANSACCIONES` → Lineage tab: raw →
   `stg_transacciones` (view) → `CREDIT_CARD_TRANSACTIONS` (mart)
   → fraud model / BI consumers. Same view answers "who reads this PII column?".

## Demo Talking Points

1. Same table, two roles → two different result sets, zero application changes.
2. Masking policies survive BI tool queries (the policy follows the column,
   not the tool); RLS filters rows by business unit at query time.
3. Enforcement (masking/RLS) is Terraform-managed; row *data* (the mapping)
   and the RLS binding live in SQL scripts — right split for review/audit.
4. Object tagging classifies PII for discovery; lineage shows its path —
   classification, enforcement and visibility in one platform.

## Quickstart Source (cloned, immutable)

| Clone | Original |
|-------|----------|
| `quickstarts/horizon-data-governance` | `sfguide-getting-started-with-horizon-data-governance-in-snowflake` |

Hardcoded-name mapping (`HRZN_*` → banking targets): see
[phase1-repository-scan.md](../../phase1-repository-scan.md).
