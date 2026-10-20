#requires -Version 7.0
<#
.SYNOPSIS
    Resets the demo state between sessions without rebuilding the environment.
.DESCRIPTION
    Removes scratch artifacts created by live demo steps (the Delta demo copy, connector probe tables, and
    the diagnostics files). Then re-runs the migration pipeline in warehouse_only mode so the migrated
    warehouse is back to a known state. Source data, lakehouse bronze tables, silver, and gold are kept.
#>
[CmdletBinding()]
param(
    [switch]$SkipPipelineRun
)

. "$PSScriptRoot/common.ps1"
$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev

Write-Step "Dropping scratch tables"
$scratch = @(
    @{ Server = $state.warehouses.wh_migrated_synapse; Database = 'wh_migrated_synapse'; Sql = "IF OBJECT_ID('dbo.zz_connector_probe') IS NOT NULL DROP TABLE dbo.zz_connector_probe;" },
    @{ Server = $state.warehouses.wh_gold;             Database = 'wh_gold';             Sql = "IF OBJECT_ID('gold.zz_demo') IS NOT NULL DROP TABLE gold.zz_demo;" }
)
foreach ($item in $scratch) {
    Invoke-WorkshopSql -Server $item.Server -Database $item.Database -Query $item.Sql | Out-Null
    Write-Host "  cleaned $($item.Database)"
}

Write-Step "Re-running the migration pipeline in warehouse_only mode"
if (-not $SkipPipelineRun) {
    Invoke-FabricItemJob -WorkspaceId $ws -ItemId $state.pipelines.pl_synapse_migration -JobType Pipeline -PollSeconds 30 -TimeoutMinutes 120 | Out-Null
    Write-Host "  pl_synapse_migration completed"
}
else { Write-Host "  skipped (-SkipPipelineRun)" }
