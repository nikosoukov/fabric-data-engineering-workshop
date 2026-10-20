#requires -Version 7.0
<#
.SYNOPSIS
    Deploys the complete workshop environment in dependency order.
.DESCRIPTION
    Order:
      01  Azure resources (F4 capacity, Synapse workspace, DW100c pool)        ~10 min
      03  Synthetic source data in Synapse (100M fact rows)                    ~10 min
      02  Fabric workspaces (Dev, Test, Prod) and Dev items
      04  Seed the Fabric SQL database (mirroring source)
      05  Warehouse DDL (wh_migrated_synapse, wh_gold)
      06  Notebooks
      nb_01 Synapse migration (full load, bronze and warehouse)                ~10 min
      07  OneLake shortcuts
      08  Pipelines and dataflow
      pl_medallion_daily run (Silver, Gold)                                    ~7 min
      09  Gold reporting views
      10  Git integration and deployment pipeline (Dev to Test)
    Use the switches to skip steps that already completed. Every script is idempotent.
#>
[CmdletBinding()]
param(
    [switch]$SkipAzure,
    [switch]$SkipPrestage,
    [switch]$SkipMigrationRun,
    [switch]$DeployToProd
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. "$here/common.ps1"
$state = Get-WorkshopState

if (-not $SkipAzure) { & "$here/01-deploy-azure.ps1" }
if (-not $SkipPrestage) { & "$here/03-prestage-synapse-source.ps1" }
& "$here/02-deploy-fabric.ps1"
& "$here/04-seed-fabric-sqldb.ps1"
& "$here/05-deploy-warehouse-ddl.ps1"
& "$here/06-deploy-notebooks.ps1"

$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev
if (-not $SkipMigrationRun) {
    Write-Step "Running nb_01_synapse_migration (full load)"
    Invoke-FabricItemJob -WorkspaceId $ws -ItemId $state.notebooks.nb_01_synapse_migration -JobType RunNotebook -PollSeconds 30 -TimeoutMinutes 180 | Out-Null
}

& "$here/07-create-shortcuts.ps1"
& "$here/08-deploy-pipelines.ps1"

Write-Step "Running pl_medallion_daily"
Invoke-FabricItemJob -WorkspaceId $ws -ItemId (Get-WorkshopState).pipelines.pl_medallion_daily -JobType Pipeline -PollSeconds 30 -TimeoutMinutes 180 | Out-Null

& "$here/09-create-gold-views.ps1"

if ($DeployToProd) { & "$here/10-git-and-deployment.ps1" -DeployToProd }
else { & "$here/10-git-and-deployment.ps1" }

Write-Step "Deployment complete. Run scripts/pause-resume.ps1 -Action Pause when the session ends."
