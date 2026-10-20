#requires -Version 7.0
<#
.SYNOPSIS
    Creates the OneLake shortcuts used by the Medallion notebooks.
.DESCRIPTION
    1. lh_bronze  Tables/bronze/core_payments  -> sqldb_core_banking mirrored table Tables/core/payments
       (a shortcut into the Fabric SQL database replica, no copy)
    2. lh_silver  Tables/bronze/*              -> lh_bronze Tables/bronze/* (lakehouse-to-lakehouse, no copy)
    Run after the bronze tables exist (nb_01) and the SQL database mirror has replicated core.payments.
    Existing shortcuts are left in place.
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/common.ps1"
$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev
$bronzeId = $state.fabric.dev.lh_bronze
$silverId = $state.fabric.dev.lh_silver
$sqlDbId  = $state.fabric.dev.sqldb_core_banking

function New-OneLakeShortcut {
    param(
        [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetItemId,
        [Parameter(Mandatory)][string]$TargetPath
    )
    $existing = Invoke-FabricApi -Method GET -Path "/workspaces/$ws/items/$ItemId/shortcuts?parentPath=$([uri]::EscapeDataString($ParentPath))"
    $found = Get-OptionalProperty -Object $existing -Name 'value'
    if ($found | Where-Object { $_.name -eq $Name }) {
        Write-Host "  exists  $ParentPath/$Name"
        return
    }
    $body = @{
        path   = $ParentPath
        name   = $Name
        target = @{ oneLake = @{ workspaceId = $ws; itemId = $TargetItemId; path = $TargetPath } }
    }
    Invoke-FabricApi -Method POST -Path "/workspaces/$ws/items/$ItemId/shortcuts" -Body $body | Out-Null
    Write-Host "  created $ParentPath/$Name -> $TargetPath"
}

Write-Step "Shortcut from lh_bronze to the Fabric SQL database mirror"
New-OneLakeShortcut -ItemId $bronzeId -ParentPath 'Tables/bronze' -Name 'core_payments' -TargetItemId $sqlDbId -TargetPath 'Tables/core/payments'

Write-Step "Shortcuts from lh_silver to lh_bronze (bronze tables, no copy)"
$bronzeTables = @('synapse_dim_date', 'synapse_dim_branch', 'synapse_dim_customer', 'synapse_dim_account', 'synapse_fact_transaction')
foreach ($t in $bronzeTables) {
    New-OneLakeShortcut -ItemId $silverId -ParentPath 'Tables/bronze' -Name $t -TargetItemId $bronzeId -TargetPath "Tables/bronze/$t"
}
New-OneLakeShortcut -ItemId $silverId -ParentPath 'Tables/bronze' -Name 'core_payments' -TargetItemId $bronzeId -TargetPath 'Tables/bronze/core_payments'
