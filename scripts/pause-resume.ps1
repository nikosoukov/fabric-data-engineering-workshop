#requires -Version 7.0
<#
.SYNOPSIS
    Resumes or pauses the billable workshop resources (Synapse dedicated pool and Fabric F4 capacity).
.DESCRIPTION
    Pause after every session to stop compute charges. Storage and item definitions are kept.
    Resume about 30 minutes before a session, then run 'Resume' and check that the pool is Online.
.PARAMETER Action
    Resume or Pause.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Resume', 'Pause')][string]$Action
)

. "$PSScriptRoot/common.ps1"
$s = Get-WorkshopSettings
$sub = $s.subscriptionId
$rg = $s.resourceGroup
$synName = $s.synapse.workspaceName
$pool = $s.synapse.sqlPoolName
$capRg = $s.fabric.capacityResourceGroup
$cap = $s.fabric.capacityName

if ($Action -eq 'Resume') {
    Write-Step "Resuming Synapse pool $pool and Fabric capacity $cap"
    az synapse sql pool resume --subscription $sub -g $rg --workspace-name $synName -n $pool -o none
    $capUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$capRg/providers/Microsoft.Fabric/capacities/$cap/resume?api-version=2023-11-01"
    az rest --method post --url $capUrl -o none
}
else {
    Write-Step "Pausing Synapse pool $pool and suspending Fabric capacity $cap"
    az synapse sql pool pause --subscription $sub -g $rg --workspace-name $synName -n $pool -o none
    $capUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$capRg/providers/Microsoft.Fabric/capacities/$cap/suspend?api-version=2023-11-01"
    az rest --method post --url $capUrl -o none
}

Write-Step "Current state"
az synapse sql pool show --subscription $sub -g $rg --workspace-name $synName -n $pool --query "{pool:name, status:status}" -o json
az resource show --subscription $sub -g $capRg -n $cap --resource-type Microsoft.Fabric/capacities --query "{capacity:name, state:properties.state}" -o json
