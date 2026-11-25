<#
  run_local.ps1 — Executa o pipeline local (Windows / PowerShell).
  Uso, na raiz do repositório:
      powershell -ExecutionPolicy Bypass -File .\run_local.ps1            # etapas padrão
      powershell -ExecutionPolicy Bypass -File .\run_local.ps1 -Etapas setup,download,db
  Etapas: setup | download | profile | db | check | stg
  Toda saída vai também para logs\run_local_<data>.log (evidência de execução).
#>
param([string[]]$Etapas = @("setup", "download", "profile", "db", "check"))

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path logs | Out-Null
$log = "logs\run_local_$(Get-Date -Format yyyyMMdd_HHmmss).log"
Start-Transcript -Path $log | Out-Null

function Run($desc, [scriptblock]$cmd) {
    Write-Host "`n=== $desc ===" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) { throw "Falhou: $desc (exit $LASTEXITCODE)" }
}

try {
    if ($Etapas -contains "setup") {
        if (-not (Test-Path .venv)) { Run "Criando .venv" { python -m venv .venv } }
        if (-not (Test-Path .env)) { Copy-Item .env.example .env; Write-Host ".env criado a partir de .env.example" }
        Run "Instalando dependências" { .\.venv\Scripts\python.exe -m pip install -q -r requirements.txt }
    }
    $py = ".\.venv\Scripts\python.exe"
    if ($Etapas -contains "download") { Run "Download das bases da ANS" { & $py -m src.extraction.download_ans } }
    if ($Etapas -contains "profile")  { Run "Profiling das bases"       { & $py -m src.exploration.profile_raw } }
    if ($Etapas -contains "db")       { Run "Schemas e controle (01)"   { sqlcmd -S localhost -E -b -i sql\01_create_schemas.sql } }
    if ($Etapas -contains "check")    { Run "Teste de conexão Python"   { & $py -m src.loading.load_stg --check } }
    if ($Etapas -contains "stg") {
        Run "Tabelas STG (02)"        { sqlcmd -S localhost -E -b -i sql\02_create_stg_tables.sql }
        Run "Carga STG"               { & $py -m src.loading.load_stg }
        Run "Evidência da carga STG"  { sqlcmd -S localhost -E -b -d ANS_BI -W -s "|" -i sql\checks\stg_resumo.sql -o logs\stg_resumo.txt; Get-Content logs\stg_resumo.txt }
    }
    Write-Host "`nOK. Log: $log" -ForegroundColor Green
}
catch {
    Write-Host "`nERRO: $_" -ForegroundColor Red
    exit 1
}
finally { Stop-Transcript | Out-Null }
