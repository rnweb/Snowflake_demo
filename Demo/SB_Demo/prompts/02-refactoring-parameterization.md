# Prompt 2 — Code Refactoring & Parameterization

> Apply the approved banking-specific naming conventions across all SQL and Python files
> in the cloned repositories. Ensure all scripts are idempotent by utilizing
> `CREATE OR REPLACE`. Foundation infrastructure (Warehouses, Databases, Schemas, Roles)
> is managed as Terraform in `Demo/SB_Demo/terraform/` — do **not** create it
> from SQL. Confirm when the refactored data/logic scripts are ready.

## Preconditions

- `naming-conventions.md` must be approved before this prompt is issued.
- Prompts are executed in order: [01](01-workspace-init-cloning.md) → [02](02-refactoring-parameterization.md) → [03](03-execution-validation.md).

## Rules

- Never execute scripts during this phase — refactoring only.
- **Infrastructure (DBs, schemas, warehouses, roles, grants, stages, policies) belongs in
  Terraform only** — strip `CREATE DATABASE/SCHEMA/ROLE/WAREHOUSE/GRANT` statements from
  refactored scripts; they are already provisioned by `terraform/`.
- Refactored scripts keep only data & logic: loads, transforms, models, apps.
- Use `CREATE OR REPLACE` / `CREATE ... IF NOT EXISTS` everywhere for idempotency.
- Abstract hardcoded values into variables at the top of each script, matching
  `terraform/terraform.tfvars`.

## Expected Output

1. Refactored copies of the Quickstart scripts (keep originals untouched in `quickstarts/`).
2. Confirmation that no infrastructure DDL remains in `scripts/` (Terraform is the
   single source of truth).
3. Confirmation message listing every changed identifier.
