#requires -Version 7.0
<#
.SYNOPSIS
    Removes the workshop environment. Destructive. Read the parameters before you run it.
.PARAMETER DeleteFabricWorkspaces
    Deletes the Dev, Test, and Prod workspaces, the deployment pipeline, and the GitHub connection.
.PARAMETER DeleteAzureResources
    Deletes the resource group rg-fabric-de-workshop (Synapse workspace, dedicated pool, default storage).
    The Fabric capacity in Fabric_Demos is not deleted. Remove it manually if you no longer need it.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DeleteFabricWorkspaces,
    [switch]$DeleteAzureResources
)

. "$PSScriptRoot/common.ps1"
$s = Get-WorkshopSettings
$state = Get-WorkshopState

if ($DeleteFabricWorkspaces) {
    if ($PSCmdlet.ShouldProcess('Fabric workspaces, deployment pipeline, and Git connection', 'Delete')) {
        if ($state.deploymentPipelineId) {
            Write-Step "Deleting deployment pipeline"
            try { Invoke-FabricApi -Method DELETE -Path "/deploymentPipelines/$($state.deploymentPipelineId)" | Out-Null } catch { Write-Warning $_.Exception.Message }
        }
        foreach ($stage in 'dev', 'test', 'prod') {
            $wsId = $state.fabric.workspaces[$stage]
            if (-not $wsId) { continue }
            Write-Step "Deleting workspace $($s.fabric.workspaces[$stage])"
            try { Invoke-FabricApi -Method DELETE -Path "/workspaces/$wsId" | Out-Null } catch { Write-Warning $_.Exception.Message }
        }
        if ($state.gitConnectionId) {
            Write-Step "Deleting GitHub credential connection"
            try { Invoke-FabricApi -Method DELETE -Path "/connections/$($state.gitConnectionId)" | Out-Null } catch { Write-Warning $_.Exception.Message }
        }
        Set-WorkshopState -State @{}
    }
}

if ($DeleteAzureResources) {
    if ($PSCmdlet.ShouldProcess("resource group $($s.resourceGroup)", 'Delete')) {
        Write-Step "Deleting resource group $($s.resourceGroup)"
        az group delete --subscription $s.subscriptionId -n $s.resourceGroup --yes --no-wait
        Write-Host "  deletion started (runs in the background)"
    }
}
