# Session 4 — Integrations & APIs (`C03`)

This session closes the **Integraciones y APIs** requirement of the
Superintendency spreadsheet: Snowflake consumes an **external API** (inbound)
through a governed Snowpark procedure with External Access, and the same
curated data is exposed to third-party tools (outbound) via the Snowflake
SQL API — connector payload for IDMC delivered below (execution pending).

## Step 1 — Provision the integration with Terraform (required first)

Run from `Demo/SB_Demo/terraform` with the full `SNOWFLAKE_*` env block:

| File | Objects |
|---|---|
| `main.tf` | Network Rule `API_CURRENCY_NETWORK_RULE` (EGRESS allow-list: `api.frankfurter.app`) + External Access Integration `API_CURRENCY_INTEGRATION` |
| `security.tf` | `USAGE` on the integration for `FR_DATA_ENGINEER` (least privilege — only this role can call procedures that use it) |

> **Guardrail:** run `terraform apply` **before** the SQL script — without the
> integration, `CREATE PROCEDURE` fails with an invalid-parameter error on
> `EXTERNAL_ACCESS_INTEGRATIONS`.

> **Account gate (verified 2026-10-21):** on the **Trial Account (Credit Card
> Attached)** `zkdcmqh-fjc41457`, `terraform apply` creates
> `API_CURRENCY_NETWORK_RULE` (62/64 resources live) but stops on the
> integration with `509009 (0A000): SQL compilation error: External access is
> not supported for trial accounts.` **External Network Access (ENA) is
> explicitly blocked on trial accounts even with a credit card attached** —
> which is why `API_CURRENCY_INTEGRATION` remains unapplied. The engineer
> `USAGE` grant cannot apply until the integration exists. Re-run Step 1 on an
> account with External Access entitlement (non-trial / contractual) before
> Step 2.

## Step 2 — Create the landing table + procedure

```bash
snowsql -f Demo/SB_Demo/scripts/session-4-integrations-apis/sql/01_api_ingestion_procedure.sql
```

The script is idempotent (`CREATE TABLE IF NOT EXISTS` + `CREATE OR REPLACE
PROCEDURE`) and runs as `FR_DATA_ENGINEER` on `WH_INGESTION_MEDIUM`, with
secondary roles disabled.

## Hook for Informatica IDMC (integration contract)

| Item | Value |
|---|---|
| Statement | `CALL SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.SP_INGEST_EXTERNAL_API();` |
| Role | `FR_DATA_ENGINEER` |
| Warehouse | `WH_INGESTION_MEDIUM` |
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

## Outbound — Snowflake SQL API payload for IDMC (Guilherme)

Second half of `C03`: the Informatica IDMC REST connector consumes the
governed mart directly from Snowflake's SQL API. Connector configuration
handed to Guilherme (2026-10-21):

| Item | Value |
|---|---|
| Method / URL | `POST https://zkdcmqh-fjc41457.snowflakecomputing.com/api/v2/statements` |
| Headers | `Authorization: Bearer <JWT>` — IDMC generates it with **Key-Pair** auth (RSA key pair), `Content-Type: application/json`, `Accept: application/json`, `X-Snowflake-Authorization-Token-Type: KEYPAIR_JWT` |

Body (JSON payload):

```json
{
  "statement": "SELECT * FROM CREDIT_CARD_TRANSACTIONS LIMIT 100",
  "timeout": 60,
  "database": "SUPERINTENDENCY_DEMO_DB",
  "schema": "CORE_BANKING_SCHEMA",
  "warehouse": "WH_INGESTION_MEDIUM",
  "role": "FR_BI_ANALYST"
}
```

- The JWT is signed with the connector user's private key;
  `X-Snowflake-Authorization-Token-Type: KEYPAIR_JWT` tells Snowflake to
  verify it against that user's registered public key (same mechanism as the
  local connector scripts).
- `FR_BI_ANALYST` is read-only and inherits the demo's governance: sensitive
  columns come back **masked** (dynamic masking + RLS stay in force for
  outbound consumers too).
- **Execution pending** — no outbound call has been made from IDMC against
  this account yet. The inbound ENA gate (`509009` above) does **not**
  affect this endpoint: ENA blocks egress *from* Snowflake, while the SQL
  API is HTTPS traffic *into* Snowflake.

## Honesty & scope notes

- **Blocked by account gate, verified 2026-10-21:** `terraform apply` on
  `zkdcmqh-fjc41457` (Trial Account — credit card attached) created the
  Network Rule but the External Access Integration failed with Snowflake
  error `509009` (*External access is not supported for trial accounts*) —
  **ENA is explicitly blocked on trial accounts even with a credit card
  attached, which is why `API_CURRENCY_INTEGRATION` remains unapplied.**
  The `USAGE` grant is consequently not applied and the procedure was
  **not** created (it requires the integration) — the `CALL` has **not**
  run on this account. Complete Steps 1-2 on a non-trial account and record
  the `Ingesta OK: <n> bytes …` evidence here. Never claim a call ran when
  it didn't.
- **Outbound (Snowflake SQL API)** over `CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS`
  with the masked `FR_BI_ANALYST` persona is the second half of `C03` — the
  IDMC connector payload (endpoint, headers, JSON body) is documented above
  and delivered to Guilherme; **execution from IDMC is pending**.
- The landing table is **raw Bronze data** (script-managed, like Session 1 raw
  tables): it intentionally has no masking/RLS — it feeds a public FX API with
  no PII.

## Related

- Session 1 (data foundation): `../session-1-lakehouse/README.md`
- Session 2 (Snowpark, Cortex & Streamlit): `../session-2-analytics-ai/README.md`
- Session 3 (governance): `../session-3-governance/README.md`
