#requires -Version 7.0
<#
.SYNOPSIS
    Creates the Fabric workspaces (Dev, Test, Prod) on the F4 capacity and the core Dev items.
.DESCRIPTION
    Items created in FDW Dev:
      lh_bronze, lh_silver           Lakehouses (Delta, Spark, schemas enabled)
      wh_gold                        Warehouse for the Gold star schema (T-SQL, BI)
      wh_migrated_synapse            Warehouse that receives the migrated Synapse tables
      sqldb_core_banking             Fabric SQL database (auto-mirrored to OneLake)
    Notebooks, pipelines, and the dataflow are added by 04-deploy-fabric-content.ps1.
    Re-running the script is safe: existing items are reused.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/common.ps1"
$s = Get-WorkshopSettings
$state = Get-WorkshopState

Write-Step "Resolving Fabric capacity '$($s.fabric.capacityName)'"
$capacity = (Get-FabricList -Path '/capacities') | Where-Object { $_.displayName -eq $s.fabric.capacityName } | Select-Object -First 1
if (-not $capacity) { throw "Capacity $($s.fabric.capacityName) is not visible to this identity. Check that the F4 capacity is Active." }
Write-Host "Capacity: $($capacity.displayName) ($($capacity.sku), $($capacity.region), id $($capacity.id))"

Write-Step "Creating workspaces on the capacity"
$workspaces = @{}
foreach ($stage in 'dev', 'test', 'prod') {
    $name = $s.fabric.workspaces.$stage
    $workspaces[$stage] = Get-OrCreateWorkspace -DisplayName $name -CapacityId $capacity.id
    Write-Host ("  {0,-5} {1}  {2}" -f $stage, $name, $workspaces[$stage])
}

$devId = $workspaces['dev']
Write-Step "Creating Dev items in $($s.fabric.workspaces.dev)"

$lhBronze = Get-OrCreateItem -WorkspaceId $devId -ItemType Lakehouse -DisplayName 'lh_bronze' -CreatePath "/workspaces/$devId/lakehouses" -Body @{ displayName = 'lh_bronze'; creationPayload = @{ enableSchemas = $true } }
$lhSilver = Get-OrCreateItem -WorkspaceId $devId -ItemType Lakehouse -DisplayName 'lh_silver' -CreatePath "/workspaces/$devId/lakehouses" -Body @{ displayName = 'lh_silver'; creationPayload = @{ enableSchemas = $true } }
$whGold   = Get-OrCreateItem -WorkspaceId $devId -ItemType Warehouse -DisplayName 'wh_gold' -CreatePath "/workspaces/$devId/warehouses" -Body @{ displayName = 'wh_gold' }
$whMig    = Get-OrCreateItem -WorkspaceId $devId -ItemType Warehouse -DisplayName 'wh_migrated_synapse' -CreatePath "/workspaces/$devId/warehouses" -Body @{ displayName = 'wh_migrated_synapse' }
$sqlDb    = Get-OrCreateItem -WorkspaceId $devId -ItemType SQLDatabase -DisplayName 'sqldb_core_banking' -CreatePath "/workspaces/$devId/sqlDatabases" -Body @{ displayName = 'sqldb_core_banking' }

$state['fabric'] = @{
    capacityId = $capacity.id
    workspaces = $workspaces
    dev = @{
        lh_bronze = $lhBronze
        lh_silver = $lhSilver
        wh_gold = $whGold
        wh_migrated_synapse = $whMig
        sqldb_core_banking = $sqlDb
    }
}
Set-WorkshopState -State $state

Write-Step "Connection details for the Dev items"
foreach ($type in @('Warehouse', 'Lakehouse', 'SQLDatabase')) {
    $items = Get-FabricList -Path "/workspaces/$devId/items?type=$type"
    foreach ($i in $items) { Write-Host ("  {0,-12} {1,-22} {2}" -f $type, $i.displayName, $i.id) }
}
Write-Host ""
Write-Host "Workspaces and items written to .workshop-state/state.json (git-ignored)." -ForegroundColor Green
