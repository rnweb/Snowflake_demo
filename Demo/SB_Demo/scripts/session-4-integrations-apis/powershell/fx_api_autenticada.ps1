# =============================================================================
# C03-AE-02 — Authenticated call to an external data API (ExchangeRate-API v6)
# =============================================================================
# The API key is read from an environment variable and never printed.
# Set it once per PowerShell session (paste it only into the terminal, before
# sharing the screen):
#     $env:FX_API_KEY = Read-Host "API key"        # Windows PowerShell 5.1 or 7
# Output: tipo_cambio_<yyyyMMdd_HHmmss>.json in the current folder, ready to be
# uploaded to @SUPERINTENDENCY_DEMO_DB.STAGING_SCHEMA.API_LANDING_STAGE
# (03_api_autenticada_stage_c03.sql).
# =============================================================================
param([string]$Base = "USD")

if (-not $env:FX_API_KEY) { throw "Defina `$env:FX_API_KEY antes de ejecutar (ver encabezado)." }

$uri     = "https://v6.exchangerate-api.com/v6/$($env:FX_API_KEY)/latest/$Base"
$archivo = "tipo_cambio_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss")

Write-Host "GET https://v6.exchangerate-api.com/v6/****/latest/$Base  (autenticado con API key)"
$resp = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 30

if ($resp.result -ne "success") { throw "La API respondió: $($resp.result) / $($resp.'error-type')" }

$resp | ConvertTo-Json -Depth 5 | Set-Content -Path $archivo -Encoding UTF8
Write-Host ("OK  base={0}  actualizado={1}  monedas={2}  USD->DOP={3}" -f `
    $resp.base_code, $resp.time_last_update_utc, ($resp.conversion_rates.PSObject.Properties | Measure-Object).Count, $resp.conversion_rates.DOP)
Write-Host "Archivo listo: $((Resolve-Path $archivo).Path)"
