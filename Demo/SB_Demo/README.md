# Snowflake Platform Demo

Snowflake demonstration project for the **Superintendency of Banks**, delivered through an
OpenCode-driven automation strategy. Full architecture and guardrails are documented in
[Architecture Documentation](https://github.com/rnweb/RF_IT_Solutions/blob/main/docs/snowflake-platform-demo/architecture.md).
A complete object inventory of everything the automation provisions (infrastructure,
data assets, AI models, governance policies) lives in
[INVENTORY.md](INVENTORY.md) next to this file.

## Demo Sessions

| Session | Theme | Assets |
|---------|-------|--------|
| 1 | Lakehouse & Data Engineering | Snowpipe, external stages, dbt project (`dbt build`) |
| 2 | AI & Analytics | Snowpark ML, Cortex RAG, Streamlit in Snowflake |
| 3 | Governance & Security | Dynamic Data Masking, Row-Level Security, access grants |

## Separation of Concerns

| Layer | Tool | Contents |
|-------|------|----------|
| **Infrastructure** | Terraform | Databases, schemas, warehouses, roles, RBAC grants, stages, masking/RLS policies |
| **Data & Logic** | Scripts | Data loading, dbt models, Snowpark ML, Streamlit / Native App code |

## Repository Structure

```
SB_Demo/
├── README.md                      # This file — overview and workflow
├── naming-conventions.md          # APPROVED original -> banking persona mapping
├── phase1-repository-scan.md      # Scan report: hardcoded names in cloned Quickstarts
├── phase3-next-steps.md           # Phase 3 runbook (Sessions 1-3, post-IaC)
├── prompts/                       # Structured prompts fed to the OpenCode agent
│   ├── 01-workspace-init-cloning.md
│   ├── 02-refactoring-parameterization.md
│   └── 03-execution-validation.md
├── dbt/                           # dbt project (pinned to FR_DATA_ENGINEER)
│   ├── dbt_project.yml            # staging views -> core marts
│   ├── profiles.yml               # role/warehouse guardrails, env-var auth
│   ├── models/                    # staging (stg_*), core (dim/incremental fact)
│   ├── macros/                    # exact-schema generate_schema_name
│   └── tests/                     # singular data-quality tests
├── quickstarts/                   # Clone target for Snowflake-Labs repos (not committed)
│   └── README.md
├── terraform/                     # Enterprise-grade IaC (source of truth for infra)
│   ├── providers.tf               # Snowflake provider + auth via SNOWFLAKE_* env vars
│   ├── variables.tf               # All object-name variables
│   ├── terraform.tfvars           # Approved banking target values
│   ├── main.tf                    # Databases, schemas, warehouses
│   ├── security.tf                # Roles, hierarchy, RBAC grants
│   └── governance.tf              # Masking policies, RLS policy + mapping table
└── scripts/                       # Data & logic (never infrastructure)
    ├── session-1-lakehouse/       # Spanish raw DDL, synthetic loader, presenter README
    ├── session-2-analytics-ai/     # Snowpark ML, Cortex AI, Streamlit app
    └── session-3-governance/      # Policy binding, mapping-table data, validation
```

## Execution Workflow

1. **Ingestion & Contextualization** — clone the Snowflake-Labs Quickstarts, produce the
   naming mapping table ([naming-conventions.md](naming-conventions.md)), execute nothing.
2. **Infrastructure Provisioning (Terraform)** — from `terraform/`:

   ```bash
   terraform init      # download the Snowflake provider
   terraform plan      # review the proposed infrastructure
   terraform apply     # provision databases, schemas, warehouses, roles, grants, policies
   ```

   Authentication via standard `SNOWFLAKE_*` environment variables — no credentials
   in files.
3. **Data & Logic Deployment** — run the scripts of each session in order
   (1 → 2 → 3), reviewing generated code before any Streamlit/Cortex/Native App deploy.
   After the Session 1 data load, set `attach_policies_to_tables = true` in
   `terraform.tfvars` and re-run `terraform apply` to bind masking policies (Session 3).
4. **Validation & Teardown** — run validation queries (row counts, masking assertions,
   Cortex responses); reset the environment with `terraform destroy` (infrastructure) and
   the session data scripts (data), or re-apply for a clean state.

Use the prompts in [prompts/](prompts/) in sequence to drive the agent through this workflow.

## Prerequisites

- Snowflake account (Enterprise/Business Critical) with a dedicated service user
- **Terraform CLI >= 1.5** with `SNOWFLAKE_*` environment variables configured
- Snowflake CLI (`snow`) / `snowsql` for script execution
- Python 3.9+ with `snowflake-snowpark-python`, `snowflake-ml-python`, `streamlit`, `dbt-snowflake`
- Git

!!! warning "Security Guardrails"
    Never hardcode credentials, restrict the agent's Snowflake role to demo-scoped grants
    (no `ACCOUNTADMIN` in daily operation), and keep a human review step before
    Streamlit/Native App/Cortex deployments.
