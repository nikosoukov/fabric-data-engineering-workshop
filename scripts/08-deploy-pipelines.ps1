#requires -Version 7.0
<#
.SYNOPSIS
    Deploys the data pipelines from pipelines/ to the Dev workspace.
.DESCRIPTION
    Tokens in the pipeline JSON are replaced with IDs from the state file:
      __WORKSPACE_ID__                     Dev workspace id
      __NOTEBOOK_ID_<notebook name>__      id of each deployed notebook
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/common.ps1"
$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev

$replacements = @{ '__WORKSPACE_ID__' = $ws }
foreach ($nb in $state.notebooks.Keys) {
    $replacements["__NOTEBOOK_ID_$($nb)__"] = $state.notebooks[$nb]
}

$dataflowIds = @{}
Get-ChildItem -Path (Join-Path $PSScriptRoot '../dataflows') -Directory | ForEach-Object {
    $name = $_.Name
    Write-Step "Deploying dataflow $name"
    $dataflowIds[$name] = Set-FabricDefinitionItem -WorkspaceId $ws -Collection dataflows -DisplayName $name -Parts @{
        'queryMetadata.json' = "dataflows/$name/queryMetadata.json"
        'mashup.pq'          = "dataflows/$name/mashup.pq"
    }
    $replacements["__DATAFLOW_ID_$($name)__"] = $dataflowIds[$name]
    Write-Host "  id: $($dataflowIds[$name])"
}
$state = Get-WorkshopState
$state['dataflows'] = $dataflowIds
Set-WorkshopState -State $state

$pipelineIds = @{}
Get-ChildItem -Path (Join-Path $PSScriptRoot '../pipelines') -Filter 'pl_*.json' | Sort-Object Name | ForEach-Object {
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    Write-Step "Deploying pipeline $name"
    $pipelineIds[$name] = Set-FabricDefinitionItem -WorkspaceId $ws -Collection dataPipelines -DisplayName $name -Parts @{ 'pipeline-content.json' = "pipelines/$($_.Name)" } -Replacements $replacements
    Write-Host "  id: $($pipelineIds[$name])"
}

$state = Get-WorkshopState
$state['pipelines'] = $pipelineIds
Set-WorkshopState -State $state
