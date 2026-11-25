<#
  run_local.ps1 — Executa o pipeline local (Windows / PowerShell).
  Uso, na raiz do repositório:
      powershell -ExecutionPolicy Bypass -File .\run_local.ps1            # etapas padrão
      powershell -ExecutionPolicy Bypass -File .\run_local.ps1 -Etapas setup,download,db
  Etapas: setup | download | profile | db | check | stg | ods | dw | export
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
    if ($Etapas -contains "db")       { Run "Schemas e controle (01)"   { sqlcmd -S localhost -E -b -I -f 65001 -i sql\01_create_schemas.sql } }
    if ($Etapas -contains "check")    { Run "Teste de conexão Python"   { & $py -m src.loading.load_stg --check } }
    if ($Etapas -contains "stg") {
        Run "Tabelas STG (02)"        { sqlcmd -S localhost -E -b -I -f 65001 -i sql\02_create_stg_tables.sql }
        Run "Carga STG"               { & $py -m src.loading.load_stg }
        Run "Evidência da carga STG"  { sqlcmd -S localhost -E -b -I -f 65001 -d ANS_BI -W -s "|" -i sql\checks\stg_resumo.sql -o logs\stg_resumo.txt; Get-Content -Encoding UTF8 logs\stg_resumo.txt }
    }
    if ($Etapas -contains "ods") {
        Run "Tabelas ODS (03)"            { sqlcmd -S localhost -E -b -I -f 65001 -i sql\03_create_ods_tables.sql }
        Run "Procedures ODS (05)"         { sqlcmd -S localhost -E -b -I -f 65001 -i sql\05_ods_stored_procedures.sql }
        Run "Procedure de pipeline (07)"  { sqlcmd -S localhost -E -b -I -f 65001 -i sql\07_pipeline_orchestration.sql }
        Run "Pipeline até o ODS"          { sqlcmd -S localhost -E -b -I -f 65001 -d ANS_BI -W -s "|" -Q "EXEC dbo.usp_Pipeline_ANS @Origem = N'run_local:ods', @AteCamada = 'ODS'" -o logs\pipeline_ods.txt; Get-Content -Encoding UTF8 logs\pipeline_ods.txt }
        Run "Evidência do ODS"            { sqlcmd -S localhost -E -b -I -f 65001 -d ANS_BI -W -s "|" -i sql\checks\ods_resumo.sql -o logs\ods_resumo.txt; Get-Content -Encoding UTF8 logs\ods_resumo.txt }
    }
    if ($Etapas -contains "dw") {
        Run "Tabelas DW (04)"             { sqlcmd -S localhost -E -b -I -f 65001 -i sql\04_create_dw_tables.sql }
        Run "Procedures DW (06)"          { sqlcmd -S localhost -E -b -I -f 65001 -i sql\06_dw_stored_procedures.sql }
        Run "Procedure de pipeline (07)"  { sqlcmd -S localhost -E -b -I -f 65001 -i sql\07_pipeline_orchestration.sql }
        Run "Pipeline completo"           { sqlcmd -S localhost -E -b -I -f 65001 -d ANS_BI -W -s "|" -Q "EXEC dbo.usp_Pipeline_ANS @Origem = N'run_local:dw'" -o logs\pipeline_dw.txt; Get-Content -Encoding UTF8 logs\pipeline_dw.txt }
        Run "Evidência do DW"             { sqlcmd -S localhost -E -b -I -f 65001 -d ANS_BI -W -s "|" -i sql\checks\dw_resumo.sql -o logs\dw_resumo.txt; Get-Content -Encoding UTF8 logs\dw_resumo.txt }
    }
    if ($Etapas -contains "export")   { Run "Exportação do DW (Parquet)" { & $py -m src.analysis.export_dw } }
    Write-Host "`nOK. Log: $log" -ForegroundColor Green
}
catch {
    Write-Host "`nERRO: $_" -ForegroundColor Red
    exit 1
}
finally { Stop-Transcript | Out-Null }
