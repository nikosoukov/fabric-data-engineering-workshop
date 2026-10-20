#requires -Version 7.0
<#
.SYNOPSIS
    Deploys the workshop notebooks from notebooks/ to the Dev workspace in Fabric git format.
.DESCRIPTION
    Each notebook sets its default lakehouse from the tokens in its META block:
      __WORKSPACE_ID__, __LAKEHOUSE_ID_BRONZE__, __LAKEHOUSE_ID_SILVER__
    The notebook's own name is the file name without the .py extension.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/common.ps1"
$s = Get-WorkshopSettings
$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev
$replacements = @{
    '__WORKSPACE_ID__'        = $ws
    '__LAKEHOUSE_ID_BRONZE__' = $state.fabric.dev.lh_bronze
    '__LAKEHOUSE_ID_SILVER__' = $state.fabric.dev.lh_silver
    '__SYNAPSE_HOST__'        = "$($s.synapse.workspaceName).sql.azuresynapse.net"
    '__SYNAPSE_POOL__'        = $s.synapse.sqlPoolName
    '__WH_MIGRATED_SERVER__'  = $state['warehouses']['wh_migrated_synapse']
    '__WH_GOLD_SERVER__'      = $state['warehouses']['wh_gold']
}

$sqlEndpoints = Get-FabricList -Path "/workspaces/$ws/items?type=SQLEndpoint"
$replacements['__SQLENDPOINT_ID_LH_SILVER__'] = ($sqlEndpoints | Where-Object { $_.displayName -eq 'lh_silver' } | Select-Object -First 1).id
$replacements['__SQLENDPOINT_ID_LH_BRONZE__'] = ($sqlEndpoints | Where-Object { $_.displayName -eq 'lh_bronze' } | Select-Object -First 1).id

$notebookIds = @{}
Get-ChildItem -Path (Join-Path $PSScriptRoot '../notebooks') -Filter 'nb_*.py' | Sort-Object Name | ForEach-Object {
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    Write-Step "Deploying notebook $name"
    $relative = "notebooks/$($_.Name)"
    $notebookIds[$name] = Set-FabricDefinitionItem -WorkspaceId $ws -Collection notebooks -DisplayName $name -Parts @{ 'notebook-content.py' = $relative } -Replacements $replacements -Format 'fabricGitSource'
    Write-Host "  id: $($notebookIds[$name])"
}

$state = Get-WorkshopState
$state['notebooks'] = $notebookIds
Set-WorkshopState -State $state
