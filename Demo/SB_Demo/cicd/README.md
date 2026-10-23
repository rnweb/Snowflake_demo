# C05 — DevOps de Datos (Azure DevOps + dbt + Snowflake)

| xlsx item | Delivered by |
|---|---|
| PRE-01 / AE-01 | dbt project in Azure Repos; change `models/analytics/*` + `schema.yml` |
| PRE-02 | Branches `main` + `feature/*`; branch policy on `main` |
| PRE-03 / AE-02 | `azure-pipelines.yml` stage **Validate**: `dbt build` on DEV with **model contract** (schema) + dbt tests (quality); artifact `dbt_package` |
| PRE-04 / PRE-06 / AE-03 | Environment **SB-PROD** with *Approvals* check (approver ≠ PR author) |
| AE-04 | Stage **Deploy_PROD**: `dbt build` on PROD + `log_deployment` → `GOVERNANCE_SCHEMA.DEPLOYMENT_LOG` + view comment |
| PRE-05 / AE-05 | Tag `v1.0.0` = stable version. Rollback = run pipeline on tag `v1.0.0` (or `git revert` PR); `DEPLOYMENT_LOG` keeps both |
| AE-06 | `sql/01_data_versioning_and_rollback.sql`: CLONE snapshot, Time Travel `AT`, restore, schema evolution, UNDROP |

## One-time setup

1. Snowflake: `sql/00_setup_dev_and_deploy_log.sql` (DEV clone + DEPLOYMENT_LOG).
2. Azure DevOps: org + project `SB-Demo`; import repo into Azure Repos.
3. Agent: 1 Microsoft-hosted parallel job (free-grant request or paid), or a
   **Linux** self-hosted agent in pool `SB-Demo-SelfHosted` (scripts are bash).
4. Library → variable group `sb-demo-snowflake`: `SNOWFLAKE_ACCOUNT`,
   `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD` (secret).
5. Environments → `SB-PROD` → Approvals and checks → Approvals (2nd user).
6. Pipelines → New → Azure Repos Git → existing YAML `Demo/SB_Demo/cicd/azure-pipelines.yml`.
7. Repos → Branches → `main` → policies: require PR, min 1 reviewer,
   Build validation = this pipeline.

## Safety

The pipeline only deploys `tag:cicd` models (views in `RISK_ANALYTICS_SCHEMA`).
Core tables are never replaced by CI, because `CREATE OR REPLACE TABLE` would
drop the Terraform-attached masking policies.
