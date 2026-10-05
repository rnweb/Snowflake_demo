# Prompt 1 — Workspace Initialization & Cloning

> You are an expert Snowflake Data Architect preparing a highly regulated banking
> demonstration. Clone the following Snowflake Quickstart repositories to the local
> workspace: [Insert Repo URLs for Snowpark, Cortex, Governance]. Once cloned, analyze
> the SQL setup files in each repository. Identify all hardcoded Database, Schema, and
> Role names. Do not execute anything yet; output a mapping table showing the original
> names and your proposed banking-specific names (e.g., `DEMO_DB` ->
> `SUPERINTENDENCY_DEMO_DB`).

## Target Quickstarts (approved)

| Area | Repository |
|------|------------|
| Data Engineering / Snowpark (Session 1) | `https://github.com/Snowflake-Labs/sfguide-getting-started-dataengineering-ml-snowpark-python` |
| dbt + Snowflake (Session 1) | `https://github.com/Snowflake-Labs/getting-started-with-dbt-on-snowflake` |
| Cortex Document Chatbot / Native App (Session 2) | `https://github.com/Snowflake-Labs/sfguide-build-chatbot-with-snowflake-native-app-snowflake-cortex` |
| Data Governance / Horizon (Session 3) | `https://github.com/Snowflake-Labs/sfguide-getting-started-with-horizon-data-governance-in-snowflake` |

Clone destination: `Demo/SB_Demo/quickstarts/` (cloned content is git-ignored).

## Expected Output

1. Cloned repositories under `quickstarts/`.
2. A mapping table of every hardcoded Database / Schema / Role / Warehouse found in SQL
   and Python files, written into `Demo/SB_Demo/naming-conventions.md`.
3. **No execution** — read-only analysis at this stage.
