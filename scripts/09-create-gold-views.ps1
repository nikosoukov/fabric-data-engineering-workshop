#requires -Version 7.0
<#
.SYNOPSIS
    Creates the reporting views in wh_gold after the gold tables are loaded.
.DESCRIPTION
    Runs sql/fabric-warehouse/03_gold_reporting_views.sql against wh_gold. Run after the Medallion pipeline.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/common.ps1"
$state = Get-WorkshopState
$server = $state.warehouses.wh_gold
Write-Step "Creating reporting views in wh_gold"
$sql = Get-Content -Raw -Path (Join-Path $PSScriptRoot '../sql/fabric-warehouse/03_gold_reporting_views.sql')
Invoke-WorkshopSql -Server $server -Database 'wh_gold' -Query $sql | Out-Null
Write-Host "  views created"
