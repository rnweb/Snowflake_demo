# VS Code + dbt setup (presenter machine)

How to run the dbt CLI from VS Code on the demo machine. The CLI is installed
but **not on PATH**, and the connection profile reads credentials from
environment variables — nothing sensitive lives in the repository.

## 1. Add dbt to PATH (one-time)

dbt ships with the system Python 3.14 install:

```
C:\Users\rnweb\AppData\Local\Python\pythoncore-3.14-64\Scripts
```

Permanent (user scope, PowerShell):

```powershell
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") +
    ";C:\Users\rnweb\AppData\Local\Python\pythoncore-3.14-64\Scripts",
  "User"
)
```

Then **restart VS Code** (or the terminal) so the new PATH is picked up.
Verify:

```powershell
dbt --version    # dbt-core 1.12.x + dbt-snowflake
```

## 2. Environment variables (one-time, user scope)

`dbt/profiles.yml` resolves the connection from the environment
(`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY_PATH`);
role, database, schema and warehouse are pinned inside the profile
(`FR_DATA_ENGINEER` / `SUPERINTENDENCY_DEMO_DB` / `STAGING_SCHEMA` /
`WH_TRANSFORM_LARGE`).

```powershell
[Environment]::SetEnvironmentVariable("SNOWFLAKE_ACCOUNT",        "zkdcmqh-fjc41457", "User")
[Environment]::SetEnvironmentVariable("SNOWFLAKE_USER",           "OPERATIONS",        "User")
[Environment]::SetEnvironmentVariable("SNOWFLAKE_PRIVATE_KEY_PATH","C:\Users\rnweb\rsa_key.p8", "User")
```

## 3. Run dbt from the project directory

All commands run from `Demo/SB_Demo/dbt` (the directory that contains
`dbt_project.yml` and `profiles.yml`):

```powershell
cd C:\Users\rnweb\OneDrive\Documentos\OpenCode\Snowflake_demo\Demo\SB_Demo\dbt

dbt debug --profiles-dir .          # connection check — every line green
dbt build  --profiles-dir .         # 6 models + 43 tests (49/49)
```

In VS Code: open the `Demo/SB_Demo` folder, then a terminal
(`Ctrl+`` `)` — the working directory is what matters; `--profiles-dir .`
tells dbt where `profiles.yml` lives.

## 4. dbt docs (lineage + model catalogue)

```powershell
cd C:\Users\rnweb\OneDrive\Documentos\OpenCode\Snowflake_demo\Demo\SB_Demo\dbt

dbt docs generate --profiles-dir .   # builds target/index.html (+ lineage graph)
dbt docs serve    --profiles-dir .   # serves docs at http://localhost:8080
```

`dbt docs generate` recompiles the project and queries the warehouse for
fresh metadata; `dbt docs serve` just serves the generated files (no
connection needed). Stop with `Ctrl+C`; the browser tab keeps working until
the server stops.

## 5. Trap — dbt rebuild detaches the RUT mask

Every plain `dbt build` re-creates `CLIENT_PROFILE_DIM`, which silently
detaches the `MASK_NATIONAL_ID` policy from its `RUT` column (the FK test
then fails at 50 M rows). After any dbt rebuild, re-attach:

```powershell
cd C:\Users\rnweb\OneDrive\Documentos\OpenCode\Snowflake_demo\Demo\SB_Demo\terraform
terraform apply -target=snowflake_table_column_masking_policy_application.national_id -auto-approve
```

(Requires the usual `SNOWFLAKE_*` Terraform variables + key-pair auth;
the apply is expected to stop afterwards with only the two trial-gated
ENAs failing — that residual plan is normal on this account.)
