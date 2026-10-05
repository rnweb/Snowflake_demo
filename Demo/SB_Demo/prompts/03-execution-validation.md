# Prompt 3 — Automated Execution & Validation

> Provision the foundation with Terraform (`terraform init && terraform plan &&
> terraform apply` in `Demo/SB_Demo/terraform/`). Then, using the configured
> `snowsql`/`snow` CLI and the active Python environment, execute the Data Governance
> scripts to bind Dynamic Data Masking to the 'NUMERO_TARJETA' and 'RUT'
> columns. Finally, write and execute a Python script that asserts the masking policy is
> working by querying the table using an admin role (should see plaintext) and
> `FR_BI_ANALYST` (should see masked data). Report the validation results.

## Execution Order

1. `cd terraform && terraform init && terraform plan && terraform apply`
2. Session 1 — Lakehouse & Engineering (`scripts/session-1-lakehouse/`)
3. Set `attach_policies_to_tables = true` in `terraform.tfvars`, re-run
   `terraform apply` (binds masking policies — Session 3 activation)
4. Session 2 — AI & Analytics (`scripts/session-2-analytics-ai/`) — **human review required
   before any Streamlit/Cortex/Native App deploy**
5. Session 3 — Governance & Security (`scripts/session-3-governance/`) — RLS policy
   binding + mapping-table data load
6. Validation queries (row counts, masking assertions, Cortex response checks)
7. Reset when a clean environment is needed:
   - data → session reset scripts
   - infrastructure → `terraform destroy`

## Expected Output

- `terraform plan`/`apply` log with created resource count.
- Execution log per script with success/failure status.
- Masking validation results: admin role → plaintext, `FR_BI_ANALYST` → masked.
- Validation summary table of row counts and asset checks.
