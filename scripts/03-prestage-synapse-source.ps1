#requires -Version 7.0
<#
.SYNOPSIS
    Creates the legacy Synapse source schema and generates synthetic data in the dedicated SQL pool.
.PARAMETER FactRows
    Rows in dbo.fact_transaction. Defaults to data.factTransactionRows in config/workshop.settings.json.
.PARAMETER SkipSchema
    Skip the DDL (use when you only want to regenerate the fact table).
#>
[CmdletBinding()]
param(
    [int]$FactRows = 0,
    [switch]$SkipSchema
)

. "$PSScriptRoot/common.ps1"
$s = Get-WorkshopSettings
if ($FactRows -le 0) { $FactRows = [int]$s.data.factTransactionRows }
$blocks = [math]::Ceiling($FactRows / 1000000)
$server = "$($s.synapse.workspaceName).sql.azuresynapse.net"
$database = $s.synapse.sqlPoolName

if (-not $SkipSchema) {
    Write-Step "Creating the legacy Synapse source schema in $database"
    $ddl = Get-Content -Raw -Path (Join-Path $PSScriptRoot '../sql/synapse/01_create_source_schema.sql')
    Invoke-WorkshopSql -Server $server -Database $database -Query $ddl | Out-Null
}

Write-Step "Generating $FactRows synthetic transactions in $database ($blocks blocks of 1M)"
$gen = (Get-Content -Raw -Path (Join-Path $PSScriptRoot '../sql/synapse/02_generate_synthetic_data.sql')).Replace('{{FACT_ROWS}}', "$FactRows").Replace('{{BLOCKS}}', "$blocks")
$timer = [Diagnostics.Stopwatch]::StartNew()
$counts = Invoke-WorkshopSql -Server $server -Database $database -Query $gen -QueryTimeoutSeconds 0
$timer.Stop()
$counts | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Elapsed: $($timer.Elapsed)"

$state = Get-WorkshopState
$state['synapse'] = @{ server = $server; database = $database; factRows = $FactRows; prestagedAt = (Get-Date).ToString('o') }
Set-WorkshopState -State $state
