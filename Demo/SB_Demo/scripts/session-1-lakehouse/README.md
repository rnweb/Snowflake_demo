# Session 1 — Data Foundation & dbt (Lakehouse)

**Audience:** Data Engineers & Architects — Superintendency of Banks.

This session demonstrates two things regulators care about: **auditable raw
ingestion** and **tested, reproducible transformations**.

1. Synthetic banking data (modeled on the official Snowflake Quickstarts)
   loaded into `SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA`
2. dbt project: staging views → core marts, with 37 data-quality tests
   (`unique`, `not_null`, `accepted_values`, `relationships`, one singular test)

## Naming mapping (Quickstart → banking persona)

| Quickstart logical | Raw table (STAGING_SCHEMA) | Key columns |
|--------------------|----------------------------|-------------|
| `CUSTOMERS`        | `CLIENTES`                 | `SSN` → **`RUT`** (national ID) |
| `CREDIT_CARDS`     | `TARJETAS_CREDITO`         | `CARD_NUMBER` → **`NUMERO_TARJETA`** |
| `TRANSACTIONS`     | `TRANSACCIONES`            | + **`UNIDAD_NEGOCIO`** (drives Session 3 RLS) |

Core marts keep the **approved** mart names consumed by the governance layer:
`CORE_BANKING_SCHEMA.CLIENT_PROFILE_DIM` (masked on `RUT`) and
`CORE_BANKING_SCHEMA.CREDIT_CARD_TRANSACTIONS` (masked on `NUMERO_TARJETA`).

## Prerequisites

- Infrastructure applied: `cd terraform && terraform init && terraform apply`
  (creates schemas, warehouses, roles and grants `FR_DEMO_ADMIN` to the
  `OPERATIONS` user so dbt can `USE ROLE FR_DATA_ENGINEER`)
- Environment variables (user scope, no secrets in the repo):

  | Variable | Value |
  |----------|-------|
  | `SNOWFLAKE_ACCOUNT` | `RBGXIGI-UAC53151` |
  | `SNOWFLAKE_USER` | `OPERATIONS` |
  | `SNOWFLAKE_PRIVATE_KEY_PATH` | path to the RSA private key (`.p8`) |
  | `SNOWFLAKE_AUTHENTICATOR` | `SNOWFLAKE_JWT` |

- Python packages: `pip install snowflake-connector-python dbt-snowflake`
  (if `dbt` is not found, add Python's `Scripts` directory to `PATH`)

## Step 1 — Raw ingestion (Spanish banking schema)

From the repository root:

```bash
python scripts/session-1-lakehouse/python/generate_and_load.py
```

The script (deterministic seed 42) generates the CSVs, runs
`sql/01_create_raw_tables.sql`, PUTs to `@RAW_STAGE` and executes
`sql/02_load_raw_data.sql` — all as **`FR_DATA_ENGINEER`** on
**`WH_INGESTION_XSMALL`**. Expected output:

```
[1/4] generated clientes            600 rows ...
[1/4] generated tarjetas_credito    928 rows ...
[1/4] generated transacciones     18000 rows ...
[2/4] connected as FR_DATA_ENGINEER on WH_INGESTION_XSMALL
       STAGING_SCHEMA.clientes              600 rows
       STAGING_SCHEMA.tarjetas_credito      928 rows
       STAGING_SCHEMA.transacciones       18000 rows
Session 1 raw ingestion complete.
```

Re-running is safe: raw tables are truncated and reloaded, and all dbt models
are rebuilt by `dbt build`.

## Step 2 — dbt transformation & data-quality tests

```bash
cd Demo/SB_Demo/dbt

dbt parse --profiles-dir .             # validate project + profile
dbt build --profiles-dir .             # run models, then run all tests
dbt source freshness --profiles-dir .  # 3/3 sources fresh
```

- `profiles.yml` pins `role: FR_DATA_ENGINEER`,
  `database: SUPERINTENDENCY_DEMO_DB`, `warehouse: WH_INGESTION_XSMALL`
- Staging layer (`STAGING_SCHEMA`): views `stg_clientes`,
  `stg_tarjetas_credito`, `stg_transacciones`
- Core layer (`CORE_BANKING_SCHEMA`): `client_profile_dim` (table),
  `credit_card_transactions` (incremental on `FECHA_TRANSACCION`)

Expected result: **`PASS=41 WARN=0 ERROR=0`** (3 views + 2 marts + 37 tests) and
**`3/3 sources fresh`**.

## Step 3 — Apache Iceberg lakehouse proof (open formats)

```bash
snowsql -f scripts/session-1-lakehouse/sql/03_iceberg_lakehouse_demo.sql
# ...or paste the file into a Snowsight worksheet
```

Run as **`FR_DATA_ENGINEER`** on **`WH_INGESTION_XSMALL`**. The script is
self-contained and re-runnable (`IF NOT EXISTS`, `TRUNCATE`, `OVERWRITE`):

1. Creates the internal stage `STAGING_SCHEMA.ICEBERG_DEMO_STAGE`
2. Exports all 18 000 mart rows to the stage as **Parquet**
   (`data_0_0_0.snappy.parquet`, ~518 KB)
3. Creates `CORE_BANKING_SCHEMA.HISTORICO_TRANSACCIONES_ICEBERG` with
   `CREATE ICEBERG TABLE ... CATALOG = 'SNOWFLAKE'`
4. Loads the full history into it

Verification (expected results):

| Check | Expected |
|-------|----------|
| `SHOW TABLES LIKE 'HISTORICO%'` | `is_iceberg = 'Y'` (Snowsight shows the Iceberg badge) |
| Row parity query | `FUENTE = 18000`, `ICEBERG = 18000` |
| `LIST @...ICEBERG_DEMO_STAGE/historico_transacciones/` | `data_0_0_0.snappy.parquet` |

Presenter talking points:

- **Open table format:** the table follows the Apache Iceberg spec — metadata
  in Avro, data in Parquet — so it stays readable by any Iceberg engine
  (Spark, Athena, Flink, Dremio) with zero vendor lock-in; regulators can
  audit the data outside Snowflake.
- **Open file format on stage:** the Parquet export on `@ICEBERG_DEMO_STAGE`
  can be read locally with DuckDB/Spark as-is
  (`duckdb -c "SELECT * FROM 'data_0_0_0.snappy.parquet' LIMIT 10"`).
- **Managed vs. external:** `CATALOG = 'SNOWFLAKE'` uses Snowflake-managed
  storage (account-local, no cloud credentials needed); `BASE_LOCATION` is
  only valid for external volumes — see `governance` notes in Session 3.
- Requires the schema privilege `CREATE ICEBERG TABLE` (granted to
  `FR_DATA_ENGINEER` in `terraform/security.tf`).

## Files

| File | Purpose |
|------|---------|
| `sql/01_create_raw_tables.sql` | Spanish raw DDL + file format + internal stage |
| `sql/02_load_raw_data.sql` | TRUNCATE + `COPY INTO` from `@RAW_STAGE` |
| `sql/03_iceberg_lakehouse_demo.sql` | Iceberg lakehouse proof: stage → Parquet → `CREATE ICEBERG TABLE` → verify |
| `python/generate_and_load.py` | Deterministic data generation + PUT + COPY + row-count check |
| `../../dbt/` | dbt project (models, tests, macros, pinned profile) |

## Quickstart Sources (cloned, immutable)

| Clone | Original |
|-------|----------|
| `quickstarts/dataengineering-ml-snowpark` | `sfguide-getting-started-dataengineering-ml-snowpark-python` |
| `quickstarts/dbt-on-snowflake` | `getting-started-with-dbt-on-snowflake` |

Hardcoded-name mapping for these repos: see
[phase1-repository-scan.md](../../phase1-repository-scan.md).
