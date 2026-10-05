# Quickstarts — Clone Target

This directory holds the cloned [Snowflake-Labs Quickstart](https://github.com/Snowflake-Labs)
repositories that serve as the immutable source of truth for the demo.

Cloned content is **git-ignored** — only this README is tracked.

## Clone Command

```bash
cd Demo/SB_Demo/quickstarts
git clone https://github.com/Snowflake-Labs/<sfguide-repo>.git
```

## Target Repositories

| Area | Repo (to confirm in prompt 1) |
|------|-------------------------------|
| Data Engineering / Snowpark | `sfguide-*` |
| dbt + Snowflake | `sfguide-dbt-snowflake-*` |
| Cortex / RAG | `sfguide-cortex-*` |
| Data Governance | `sfguide-*governance*` |

> Exact URLs are inserted into [prompt 1](../prompts/01-workspace-init-cloning.md)
> before execution. The agent analyzes them read-only first — nothing is executed
> until [prompt 3](../prompts/03-execution-validation.md).
