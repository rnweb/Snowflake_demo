# Ordem de execução — conta antiga → conta nova

Regra: toda mudança no Snowflake sai de um arquivo deste repositório. Nada é
criado à mão no Snowsight. Para subir a conta nova, basta seguir esta tabela de
cima para baixo, pulando o que já está ✅ na coluna da conta nova.

- **Conta antiga:** `RBGXIGI-UAC53151` (locator `FFC63811`), trial que expira por volta de 29/10/2026.
- **Conta nova:** `ZKDCMQH-FJC41457` (locator `PKC86765`), trial com cartão.
- **Conferência:** `scripts/bootstrap/99_inventario_conta.sql` rodado nas duas contas em 22/10/2026; a coluna "Conta nova" reflete esse inventário.
- **Legenda:** ✅ executado · ⏳ pendente · ⚠️ parcial · ⛔ bloqueado · — não se aplica.

| # | Arquivo | Executa como | Conta antiga | Conta nova | Observação |
|---|---|---|---|---|---|
| 1 | `terraform/` (main, security, governance) | Terraform | ✅ | ✅ 62/64 | Faltam External Access Integration + grant (bloqueio de trial `509009`) |
| 1b | `terraform/integrations.tf` (IDMC_LANDING_SCHEMA, FR_IDMC_INTEGRATION, FR_CATALOG_READER, usuários SVC_IDMC_CDI/SVC_IDMC_CDGC e DEMO_ANALYST + grants) | Terraform | ✅ | ⏳ | **Pré-requisito de toda a parte IDMC/CDGC e do Power BI** na conta nova. Senhas só via `TF_VAR_*`. Rodar antes o bloco final do `00_accountadmin_bootstrap.sql` (CREATE USER para FR_TERRAFORM) |
| 2 | `scripts/bootstrap/00_accountadmin_bootstrap.sql` | ACCOUNTADMIN | ✅ | ✅ | |
| 3 | `scripts/session-1-lakehouse/sql/01_create_raw_tables.sql` | FR_DATA_ENGINEER | ✅ | ✅ | |
| 3b | `scripts/session-1-lakehouse/sql/03_iceberg_lakehouse_demo.sql` | FR_DATA_ENGINEER | ✅ | ✅ | `HISTORICO_TRANSACCIONES_ICEBERG` + `ICEBERG_DEMO_STAGE` criados em 22/10 na nova conta: paridade 50.000.000 = 50.000.000 (export com máscara ativa → tokens) |
| 4 | `scripts/session-1-lakehouse/python/generate_and_load.py` + `sql/02_load_raw_data.sql` | FR_DATA_ENGINEER | ✅ | ✅ | 600 clientes, 928 cartões nas duas; transações 18.000 (antiga) / 50.000.000 (nova, PG-06) |
| 5 | `dbt build` (staging + core) | FR_DATA_ENGINEER | ✅ | ✅ | Marts 600 / 50.000.000 na nova (600 / 18.000 na antiga). Nunca `CREATE OR REPLACE` depois do passo 6. **Cada `dbt build` recria `CLIENT_PROFILE_DIM` e destaca a máscara da coluna RUT** → reaplicar `terraform apply -target=snowflake_table_column_masking_policy_application.national_id` após qualquer build (o `--full-refresh` destaca também `national_id_fact`/`credit_card` + RLS) |
| 6 | `scripts/session-3-governance/sql/01_seed_role_mapping.sql` | FR_DEMO_ADMIN | ✅ (11 linhas) | ⚠️ (4 linhas) | Reexecutar **depois do 1b** (precisa das roles IDMC/catálogo) |
| 7 | `scripts/session-3-governance/sql/02_verify_masking_rls.sql` | — | ✅ | ⏳ | Máscaras e RLS já aplicadas nos marts da conta nova; só validar |
| 8 | `scripts/session-3-governance/sql/03_object_tagging_demo.sql` | FR_DEMO_ADMIN | ✅ | ⏳ | Tag `DATA_CLASSIFICATION` não existe na nova |
| 9 | Mappings IDMC (mt_SB_Comercios_Maestro, mt_SB_Riesgo_por_Rubro) | IDMC | ✅ | ⏳ | Reapontar a conexão Snowflake do IDMC para a conta nova; cria `COMERCIOS_MAESTRO` (18) e `RIESGO_POR_RUBRO` (33) na conta antiga — na nova os agregados somarão 50.000.000 |
| 10 | `scripts/bootstrap/01_post_idmc_grants.sql` | FR_DEMO_ADMIN | ✅ | ⏳ | RLS em `RIESGO_POR_RUBRO`; validado na antiga (5849 ao analista), na nova espera 15.969.793 (RETAIL) |
| 11 | `scripts/session-3-governance/sql/04_audit_logs.sql` | ACCOUNTADMIN | ⚠️ (sem `AUDIT_QUERY_LOG`) | ⏳ | Contém comandos que **devem falhar** (AE-05) |
| 12 | `scripts/session-3-governance/sql/05_external_access_marketplace.sql` — bloco 0 | ACCOUNTADMIN | ✅ | ⏳ | Blocos A/C são da demo. **Reexecutar o passo 6 apaga a linha FR_EXTERNAL_READER: rodar o bloco 0 de novo depois** |
| 13 | `scripts/session-3-governance/sql/06_cai_marketplace_provisioner.sql` | ACCOUNTADMIN | ⏳ | ⏳ | Rodar **só na conta nova**. Token (PAT) aparece uma vez: direto para a conexão do CAI |
| 13b | `scripts/session-1-lakehouse/sql/04_cdc_streams_tasks.sql` | ACCOUNTADMIN → FR_DATA_ENGINEER | ⏳ | ⏳ | Rodar **só na conta nova** (C01-AE-05, C02-AE-01/04/05/06, C02-PRE-05) |
| 14 | `cicd/sql/00_setup_dev_and_deploy_log.sql` | ACCOUNTADMIN | ⏳ | ⏳ | Rodar **só na conta nova**. Pré-requisito do C05 |
| 15 | `scripts/session-2-analytics-ai/sql/02_cortex_ai_features.sql` | FR_DATA_ENGINEER | ⛔ `399258` | ✅ | `CORTEX_VECTOR_STORE.DOCUMENTS` com 3 documentos |
| 16 | `scripts/session-2-analytics-ai/sql/04_deploy_streamlit.sql` | FR_DATA_ENGINEER | ✅ | ✅ | `PANEL_PREVENCION_FRAUDE` |
| 17 | CDGC: rescan Snowflake_SB_Demo (Completo) | IDMC | ✅ | ⏳ | Depois dos passos 9 e 10 |
| 18 | CAI: conexão Snowflake (SVC_CAI_MARKETPLACE) | IDMC | — | ⏳ | Trocar o stub dos processos p_SB_MP_* |
| 19 | Power BI: trocar servidor | Power BI | ✅ | ⏳ | DirectQuery com DEMO_ANALYST (criado no passo 1b) |
| 20 | `scripts/session-4-integrations-apis/sql/01_api_ingestion_procedure.sql` | FR_DATA_ENGINEER | ⛔ | ⛔ `509009` | Network rule já existe na nova; integração bloqueada em trial. Alternativa: ingestão pela IDMC |
| 21 | `scripts/bootstrap/99_inventario_conta.sql` | ACCOUNTADMIN | ✅ | ✅ | Rodar de novo ao final para conferir; depois `DROP DATABASE ZZ_INVENTARIO` |

Diferenças que não exigem ação: as políticas de máscara/RLS têm o mesmo corpo,
só muda o tamanho máximo padrão de VARCHAR entre as contas; `COMPUTE_WH` tem
auto-suspend 300 s na nova (600 s na antiga). As roles `APP_ADMIN` e
`APP_DEVELOPER` existem só na antiga e não aparecem em nenhum script: foram
criadas à mão e não são usadas pela demo.

Ao executar um passo, atualize a coluna da conta correspondente no mesmo commit.
