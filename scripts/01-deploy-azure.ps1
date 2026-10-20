#requires -Version 7.0
<#
.SYNOPSIS
    Deploys the Azure resources for the workshop: resource group, Fabric F4 capacity, Synapse workspace,
    the DW100c dedicated SQL pool, and the Synapse default storage account.
.DESCRIPTION
    Uses Azure CLI sign-in (az login). No passwords are stored. The Synapse SQL admin password is generated in
    memory, used once to create the workspace, then discarded. Entra authentication is used everywhere else.
    Firewall: "Allow Azure services" (0.0.0.0) is enabled on Synapse so Fabric Spark can reach the pool. Your
    client IP is also added. Tighten this with private endpoints for production.
    Re-running is safe: existing resources are reused.
.PARAMETER ClientIp
    Your public IP address to allow on the Synapse firewall. Detected automatically when omitted.
#>
[CmdletBinding()]
param(
    [string]$ClientIp
)

. "$PSScriptRoot/common.ps1"
$s = Get-WorkshopSettings
$sub = $s.subscriptionId
$rg = $s.resourceGroup
$location = $s.location
$storageName = $s.storage.accountName
$synName = $s.synapse.workspaceName

Write-Step "Resource group $rg ($location)"
az group create --subscription $sub -n $rg -l $location --tags purpose=fabric-workshop -o none
if ($LASTEXITCODE -ne 0) { throw "Could not create resource group $rg." }

Write-Step "Fabric capacity $($s.fabric.capacityName) ($($s.fabric.capacitySku)) in $($s.fabric.capacityResourceGroup)"
$capUrl = "https://management.azure.com/subscriptions/$sub/resourceGroups/$($s.fabric.capacityResourceGroup)/providers/Microsoft.Fabric/capacities/$($s.fabric.capacityName)?api-version=2023-11-01"
$capBody = @{
    location   = $location
    sku        = @{ name = $s.fabric.capacitySku; tier = 'Fabric' }
    properties = @{ administration = @{ members = @($s.fabric.capacityAdmin) } }
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) "fdw-capacity-$([guid]::NewGuid()).json"
Set-Content -Path $tmp -Value (ConvertTo-Json $capBody -Depth 6) -Encoding ascii
try {
    az rest --method put --url $capUrl --body "@$tmp" -o none
    if ($LASTEXITCODE -ne 0) { throw "Capacity create/update failed." }
}
finally { Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
$capState = az resource show --subscription $sub -g $s.fabric.capacityResourceGroup -n $s.fabric.capacityName --resource-type Microsoft.Fabric/capacities --query properties.state -o tsv
Write-Host "  capacity state: $capState"

Write-Step "Storage account $storageName (Synapse default data lake)"
az storage account create --subscription $sub -g $rg -n $storageName -l $location --sku Standard_LRS --kind StorageV2 --hns true --min-tls-version TLS1_2 --allow-blob-public-access false -o none
az storage container-rm create --subscription $sub --storage-account $storageName -g $rg -n synapse-fs -o none

Write-Step "Synapse workspace $synName"
$synExists = az synapse workspace show --subscription $sub -g $rg -n $synName --query name -o tsv 2>$null
if (-not $synExists) {
    $pw = 'Aa1!' + (-join ((48..57 + 65..90 + 97..122) | Get-Random -Count 28 | ForEach-Object { [char]$_ }))
    az synapse workspace create --subscription $sub -g $rg -n $synName -l $location --storage-account $storageName --file-system synapse-fs --sql-admin-login-user $s.synapse.sqlAdminLogin --sql-admin-login-password $pw -o none
    $pw = $null
    if ($LASTEXITCODE -ne 0) { throw "Synapse workspace create failed." }
}
$msi = az synapse workspace show --subscription $sub -g $rg -n $synName --query identity.principalId -o tsv
$scope = az storage account show --subscription $sub -g $rg -n $storageName --query id -o tsv
az role assignment create --subscription $sub --assignee-object-id $msi --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $scope -o none 2>$null

Write-Step "Dedicated SQL pool $($s.synapse.sqlPoolName) ($($s.synapse.sqlPoolServiceLevel))"
$poolExists = az synapse sql pool show --subscription $sub -g $rg --workspace-name $synName -n $s.synapse.sqlPoolName --query name -o tsv 2>$null
if (-not $poolExists) {
    az synapse sql pool create --subscription $sub -g $rg --workspace-name $synName --name $s.synapse.sqlPoolName --performance-level $s.synapse.sqlPoolServiceLevel --collation SQL_Latin1_General_CP1_CI_AS -o none
}

Write-Step "Synapse firewall"
az synapse workspace firewall-rule create --subscription $sub -g $rg --workspace-name $synName -n AllowAllWindowsAzureIps --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none
if (-not $ClientIp) { $ClientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim() }
az synapse workspace firewall-rule create --subscription $sub -g $rg --workspace-name $synName -n ClientIp-Presenter --start-ip-address $ClientIp --end-ip-address $ClientIp -o none
Write-Host "  allowed Azure services and client IP $ClientIp"

Write-Step "Done. Next: 02-deploy-fabric.ps1 (workspaces and items), then 03-prestage-synapse-source.ps1"
