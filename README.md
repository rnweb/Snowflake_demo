# Snowflake Demo

Repository for all **Snowflake demos, POCs and tests** maintained by RF IT
Solutions — one folder per engagement, Terraform-managed infrastructure, and
presenter-ready runbooks.

## Layout

| Folder | Purpose |
|--------|---------|
| [`Demo/`](Demo/) | Full, presenter-ready demos (infrastructure + data + scripts) |
| [`POC/`](POC/) | Targeted proofs of concept |
| [`Tests/`](Tests/) | Validation scripts and exploratory tests |

## Demos

| Demo | Folder | Description |
|------|--------|-------------|
| **SB_Demo** — Superintendency of Banks | [`Demo/SB_Demo/`](Demo/SB_Demo/) | Three-session platform demo: Session 1 lakehouse & dbt, Session 2 Snowpark ML / Cortex AI / Streamlit, Session 3 Horizon governance (masking, row-level security, object tagging) — all RBAC and policies via Terraform |

Start each demo from its own `README.md`; the complete object inventory
(databases, tables, policies, roles, AI assets) lives next to it as
[`Demo/SB_Demo/INVENTORY.md`](Demo/SB_Demo/INVENTORY.md).
