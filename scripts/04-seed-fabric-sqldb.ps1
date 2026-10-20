#requires -Version 7.0
<#
.SYNOPSIS
    Seeds the Fabric SQL database (sqldb_core_banking) with synthetic core-banking data. Mirroring replicates it to OneLake.
.DESCRIPTION
    Runs sql/fabric-sqldb/01_core_banking_seed.sql. The connection values come from the item properties.
    Synthetic data only. Safe to rerun because the tables are dropped and recreated.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/common.ps1"
$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev
$db = Invoke-FabricApi -Method GET -Path "/workspaces/$ws/sqlDatabases/$($state.fabric.dev.sqldb_core_banking)"
$server = ($db.properties.serverFqdn -split ',')[0]
$database = $db.properties.databaseName

Write-Step "Seeding $database on $server"
$sql = Get-Content -Raw -Path (Join-Path $PSScriptRoot '../sql/fabric-sqldb/01_core_banking_seed.sql')
Invoke-WorkshopSql -Server $server -Database $database -Query $sql -QueryTimeoutSeconds 1800 | Format-Table | Out-String | Write-Host

$state = Get-WorkshopState
$state['sqldb'] = @{ server = $server; database = $database }
Set-WorkshopState -State $state
