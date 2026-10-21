# Session 4 — Integrations & APIs (`C03`)

This session closes the **Integraciones y APIs** requirement of the
Superintendency spreadsheet: Snowflake consumes an **external API** (inbound)
through a governed Snowpark procedure with External Access, and the same
curated data will be exposed to third-party tools (outbound) via the Snowflake
SQL API — delivered as a follow-up of this session.

## Step 1 — Provision the integration with Terraform (required first)

Run from `Demo/SB_Demo/terraform` with the full `SNOWFLAKE_*` env block:

| File | Objects |
|---|---|
| `main.tf` | Network Rule `API_CURRENCY_NETWORK_RULE` (EGRESS allow-list: `api.frankfurter.app`) + External Access Integration `API_CURRENCY_INTEGRATION` |
| `security.tf` | `USAGE` on the integration for `FR_DATA_ENGINEER` (least privilege — only this role can call procedures that use it) |

> **Guardrail:** run `terraform apply` **before** the SQL script — without the
> integration, `CREATE PROCEDURE` fails with an invalid-parameter error on
> `EXTERNAL_ACCESS_INTEGRATIONS`.

## Step 2 — Create the landing table + procedure

```bash
snowsql -f Demo/SB_Demo/scripts/session-4-integrations-apis/sql/01_api_ingestion_procedure.sql
```

The script is idempotent (`CREATE TABLE IF NOT EXISTS` + `CREATE OR REPLACE
PROCEDURE`) and runs as `FR_DATA_ENGINEER` on `WH_INGESTION_XSMALL`, with
secondary roles disabled.

## Hook for Informatica IDMC (integration contract)

| Item | Value |
|---|---|
| Statement | `CALL SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.SP_INGEST_EXTERNAL_API();` |
| Role | `FR_DATA_ENGINEER` |
| Warehouse | `WH_INGESTION_XSMALL` |
| Success | returns `Ingesta OK: <n> bytes de api.frankfurter.app` |
| Failure | raises a SQL exception — network/HTTP errors propagate **on purpose** (no try/except), so the mapping fails visibly instead of reporting a false success |
| Output | one new row per CALL in `SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.API_RAW_CURRENCY_DATA` (`RAW_PAYLOAD` VARIANT, `INGESTION_TIME` LTZ) |

## Verification (evidence)

```sql
USE SECONDARY ROLES NONE;
USE ROLE FR_DATA_ENGINEER;
-- +1 row per successful CALL
SELECT COUNT(*) FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.API_RAW_CURRENCY_DATA;
-- latest payload, FX rates for USD
SELECT INGESTION_TIME,
       RAW_PAYLOAD:base::string                     AS BASE,
       RAW_PAYLOAD:rates.BRL::float                 AS BRL,
       RAW_PAYLOAD:rates.CLP::float                 AS CLP,
       RAW_PAYLOAD:rates.MXN::float                 AS MXN
FROM SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.API_RAW_CURRENCY_DATA
ORDER BY INGESTION_TIME DESC
LIMIT 1;
```

## Honesty & scope notes

- **Not yet executed end-to-end on the live account** (validation pending on the
  trial account — this procedure needs External Access, which is unverified
  there). If the account blocks it, document the exact gate here like the
  Cortex `399258` one; never claim a call ran when it didn't.
- **Outbound (Snowflake SQL API)** over `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS`
  with the masked `FR_BI_ANALYST` persona is the second half of `C03` —
  delivered in a follow-up, not in this PR.
- The landing table is **raw Bronze data** (script-managed, like Session 1 raw
  tables): it intentionally has no masking/RLS — it feeds a public FX API with
  no PII.

## Related

- Session 1 (data foundation): `../session-1-lakehouse/README.md`
- Session 2 (Snowpark, Cortex & Streamlit): `../session-2-analytics-ai/README.md`
- Session 3 (governance): `../session-3-governance/README.md`
