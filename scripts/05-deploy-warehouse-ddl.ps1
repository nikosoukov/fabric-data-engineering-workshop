#requires -Version 7.0
<#
.SYNOPSIS
    Applies the T-SQL schema scripts to the Fabric warehouses (wh_migrated_synapse and wh_gold).
.DESCRIPTION
    Runs sql/fabric-warehouse/01 to wh_migrated_synapse and sql/fabric-warehouse/02 to wh_gold.
    Reporting views (03) are applied later, after the gold tables are loaded, by 09-create-gold-views.ps1.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/common.ps1"
$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev

function Get-WarehouseEndpoint {
    param([string]$ItemId)
    $wh = Invoke-FabricApi -Method GET -Path "/workspaces/$ws/warehouses/$ItemId"
    return $wh.properties.connectionString
}

$deployments = @(
    @{ Name = 'wh_migrated_synapse'; Id = $state.fabric.dev.wh_migrated_synapse; Script = 'sql/fabric-warehouse/01_create_migrated_schema.sql' },
    @{ Name = 'wh_gold';             Id = $state.fabric.dev.wh_gold;             Script = 'sql/fabric-warehouse/02_create_gold_schema.sql' },
    @{ Name = 'wh_gold';             Id = $state.fabric.dev.wh_gold;             Script = 'sql/fabric-warehouse/04_usp_load_gold.sql' }
)
foreach ($d in $deployments) {
    Write-Step "Applying $($d.Script) to $($d.Name)"
    $server = Get-WarehouseEndpoint -ItemId $d.Id
    $sql = Get-Content -Raw -Path (Join-Path $PSScriptRoot "../$($d.Script)")
    Invoke-WorkshopSql -Server $server -Database $d.Name -Query $sql -QueryTimeoutSeconds 600 | Out-Null
    Write-Host "  done"
    $state = Get-WorkshopState
    if (-not $state.ContainsKey('warehouses')) { $state['warehouses'] = @{} }
    $state['warehouses'][$d.Name] = $server
    Set-WorkshopState -State $state
}
