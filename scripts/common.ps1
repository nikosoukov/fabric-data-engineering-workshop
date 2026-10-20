#requires -Version 7.0
<#
.SYNOPSIS
    Shared helpers for the Fabric for Data Engineers workshop scripts.
.DESCRIPTION
    Dot-source this file from other scripts:  . "$PSScriptRoot/common.ps1"
    Authentication uses your Azure CLI sign-in (az login). No passwords or keys are stored.
    Local state (workspace and item IDs) is written to .workshop-state/state.json, which is git-ignored.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot     = Split-Path -Parent $PSScriptRoot
$script:SettingsPath = Join-Path $script:RepoRoot 'config/workshop.settings.json'
$script:StatePath    = Join-Path $script:RepoRoot '.workshop-state/state.json'
$script:Settings     = Get-Content -Raw -Path $script:SettingsPath | ConvertFrom-Json

function Get-WorkshopSettings { return $script:Settings }

function Get-WorkshopState {
    if (Test-Path $script:StatePath) {
        return Get-Content -Raw -Path $script:StatePath | ConvertFrom-Json -AsHashtable
    }
    return @{}
}

function Set-WorkshopState {
    param([Parameter(Mandatory)][hashtable]$State)
    New-Item -ItemType Directory -Force -Path (Split-Path $script:StatePath) | Out-Null
    $State | ConvertTo-Json -Depth 10 | Set-Content -Path $script:StatePath -Encoding utf8
}

function Get-AccessToken {
    param([Parameter(Mandatory)][string]$Resource)
    $token = az account get-access-token --subscription $script:Settings.subscriptionId --resource $Resource --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Could not get a token for $Resource. Run 'az login' and check subscriptionId in config/workshop.settings.json."
    }
    return $token
}

function ConvertTo-Base64Text {
    param([Parameter(Mandatory)][string]$Text)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Invoke-FabricApi {
    <#
      Calls the Fabric REST API. Long-running operations (HTTP 202) are polled until they finish,
      and the operation result is returned when one exists.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )
    $headers = @{ Authorization = "Bearer $(Get-AccessToken -Resource 'https://api.fabric.microsoft.com')" }
    $params = @{
        Method                 = $Method
        Uri                    = "https://api.fabric.microsoft.com/v1$Path"
        Headers                = $headers
        SkipHttpErrorCheck     = $true
        StatusCodeVariable     = 'status'
        ResponseHeadersVariable = 'respHeaders'
    }
    if ($null -ne $Body) {
        $params.Body        = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
        $params.ContentType = 'application/json'
    }
    $result = Invoke-RestMethod @params
    if ($status -ge 400) {
        throw "Fabric API $Method $Path failed with HTTP $status : $(ConvertTo-Json -InputObject $result -Depth 5 -Compress)"
    }
    if ($status -eq 202) {
        $opUrl = $respHeaders['Location'] | Select-Object -First 1
        $retry = [int]($respHeaders['Retry-After'] | Select-Object -First 1)
        if ($retry -le 0) { $retry = 5 }
        do {
            Start-Sleep -Seconds $retry
            $op = Invoke-RestMethod -Method Get -Uri $opUrl -Headers $headers -SkipHttpErrorCheck -StatusCodeVariable opStatus -ResponseHeadersVariable opHeaders
            $opState = Get-OptionalProperty -Object $op -Name 'status'
        } while ($opState -in @('NotStarted', 'Running'))
        if ($opState -ne 'Succeeded') {
            throw "Fabric operation $Path ended with status $opState : $(ConvertTo-Json -InputObject $op -Depth 5 -Compress)"
        }
        try { return Invoke-RestMethod -Method Get -Uri "$opUrl/result" -Headers $headers } catch { return $null }
    }
    return $result
}

function Get-OptionalProperty {
    <# Reads a property that may be absent (Set-StrictMode would otherwise throw). #>
    param([object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Get-FabricList {
    <# Returns every item from a paginated Fabric list endpoint. #>
    param([Parameter(Mandatory)][string]$Path)
    $items = @()
    $next = $Path
    while ($next) {
        $page = Invoke-FabricApi -Method GET -Path $next
        $value = Get-OptionalProperty -Object $page -Name 'value'
        if ($value) { $items += $value }
        $token = Get-OptionalProperty -Object $page -Name 'continuationToken'
        if ($token) {
            $sep = if ($Path.Contains('?')) { '&' } else { '?' }
            $next = "$Path$($sep)continuationToken=$token"
        }
        else { $next = $null }
    }
    return $items
}

function Get-OrCreateWorkspace {
    param([Parameter(Mandatory)][string]$DisplayName, [Parameter(Mandatory)][string]$CapacityId)
    $existing = (Get-FabricList -Path '/workspaces') | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($existing) {
        if ((Get-OptionalProperty -Object $existing -Name 'capacityId') -ne $CapacityId) {
            Invoke-FabricApi -Method POST -Path "/workspaces/$($existing.id)/assignToCapacity" -Body @{ capacityId = $CapacityId } | Out-Null
        }
        return $existing.id
    }
    $ws = Invoke-FabricApi -Method POST -Path '/workspaces' -Body @{ displayName = $DisplayName; capacityId = $CapacityId }
    return $ws.id
}

function Get-OrCreateItem {
    <#
      Finds an item by type and name in a workspace, or creates it with the type-specific create endpoint.
      -Body is the create payload. For generic item creation with a definition, pass -CreatePath '/workspaces/{id}/items'.
    #>
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$ItemType,          # Lakehouse | Warehouse | SQLDatabase | Notebook | DataPipeline | Dataflow
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$CreatePath,
        [object]$Body
    )
    $found = (Get-FabricList -Path "/workspaces/$WorkspaceId/items?type=$ItemType") | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($found) { return $found.id }
    if (-not $CreatePath) { $CreatePath = "/workspaces/$WorkspaceId/items" }
    if (-not $Body) { $Body = @{ displayName = $DisplayName; type = $ItemType } }
    $created = Invoke-FabricApi -Method POST -Path $CreatePath -Body $Body
    $createdId = Get-OptionalProperty -Object $created -Name 'id'
    if ($createdId) { return $createdId }
    $found = (Get-FabricList -Path "/workspaces/$WorkspaceId/items?type=$ItemType") | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if (-not $found) { throw "Item $DisplayName ($ItemType) was not found after creation." }
    return $found.id
}

function Invoke-WorkshopSql {
    <#
      Runs T-SQL against Synapse dedicated SQL pool, Azure SQL, Fabric SQL database, or a Fabric Warehouse
      using an Entra access token. Batches separated by GO are supported.
    #>
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$Query,
        [int]$QueryTimeoutSeconds = 0
    )
    $token = Get-AccessToken -Resource 'https://database.windows.net/'
    Invoke-Sqlcmd -ServerInstance $Server -Database $Database -AccessToken $token -Query $Query -QueryTimeout $QueryTimeoutSeconds -TrustServerCertificate -ErrorAction Stop
}

function Get-FabricPartDefinition {
    <# Builds one part of an item definition from a local file. #>
    param([Parameter(Mandatory)][string]$LocalPath, [Parameter(Mandatory)][string]$PartPath)
    $text = Get-Content -Raw -Path $LocalPath
    return @{ path = $PartPath; payload = (ConvertTo-Base64Text -Text $text); payloadType = 'InlineBase64' }
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ""
    Write-Host ("==> " + $Message) -ForegroundColor Cyan
    }

    function Set-FabricDefinitionItem {
        <#
          Creates or updates a notebook, data pipeline, or dataflow from files in the repo.
          -Parts maps the item definition part path to a local file. Each file can contain tokens such as
          __WORKSPACE_ID__ or __LAKEHOUSE_ID_BRONZE__. -Replacements supplies their values.
          Returns the item id.
        #>
        param(
            [Parameter(Mandatory)][string]$WorkspaceId,
            [Parameter(Mandatory)][ValidateSet('notebooks', 'dataPipelines', 'dataflows')][string]$Collection,
            [Parameter(Mandatory)][string]$DisplayName,
            [Parameter(Mandatory)][hashtable]$Parts,
            [hashtable]$Replacements = @{},
            [string]$Format
        )
        $partList = @()
        foreach ($partPath in $Parts.Keys) {
            $text = Get-Content -Raw -Path (Join-Path $script:RepoRoot $Parts[$partPath])
            foreach ($k in $Replacements.Keys) { $text = $text.Replace($k, [string]$Replacements[$k]) }
            $partList += @{ path = $partPath; payload = (ConvertTo-Base64Text -Text $text); payloadType = 'InlineBase64' }
        }
        $definition = @{ parts = $partList }
        if ($Format) { $definition.format = $Format }

        $existing = (Get-FabricList -Path "/workspaces/$WorkspaceId/$Collection") | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
        if ($existing) {
            Write-Host "  updating $DisplayName"
            Invoke-FabricApi -Method POST -Path "/workspaces/$WorkspaceId/$Collection/$($existing.id)/updateDefinition?updateMetadata=false" -Body @{ definition = $definition } | Out-Null
            return $existing.id
        }
        Write-Host "  creating $DisplayName"
        $created = Invoke-FabricApi -Method POST -Path "/workspaces/$WorkspaceId/$Collection" -Body @{ displayName = $DisplayName; definition = $definition }
        $createdId = Get-OptionalProperty -Object $created -Name 'id'
        if ($createdId) { return $createdId }
        $existing = (Get-FabricList -Path "/workspaces/$WorkspaceId/$Collection") | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
        return $existing.id
    }

    function Invoke-FabricItemJob {
        <#
          Starts a job for a notebook (RunNotebook) or a data pipeline (Pipeline), waits for it to finish,
          and returns the final job. Throws if the job does not complete.
        #>
        param(
            [Parameter(Mandatory)][string]$WorkspaceId,
            [Parameter(Mandatory)][string]$ItemId,
            [ValidateSet('RunNotebook', 'Pipeline')][string]$JobType = 'RunNotebook',
            [int]$PollSeconds = 20,
            [int]$TimeoutMinutes = 180
        )
        $headers = @{ Authorization = "Bearer $(Get-AccessToken -Resource 'https://api.fabric.microsoft.com')" }
        $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$ItemId/jobs/instances?jobType=$JobType"
        $resp = Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -SkipHttpErrorCheck -ContentType 'application/json' -Body '{}'
        if ([int]$resp.StatusCode -ge 400) { throw "Could not start $JobType job ($($resp.StatusCode)): $($resp.Content)" }
        $location = $resp.Headers['Location'] | Select-Object -First 1
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        do {
            Start-Sleep -Seconds $PollSeconds
            $job = Invoke-RestMethod -Method Get -Uri $location -Headers @{ Authorization = "Bearer $(Get-AccessToken -Resource 'https://api.fabric.microsoft.com')" }
            $jobStatus = Get-OptionalProperty -Object $job -Name 'status'
            if ((Get-Date) -gt $deadline) { throw "$JobType job for $ItemId did not finish within $TimeoutMinutes minutes." }
        } while ($jobStatus -in @('NotStarted', 'InProgress'))
        if ($jobStatus -ne 'Completed') {
            $reason = Get-OptionalProperty -Object $job -Name 'failureReason'
            throw "$JobType job for $ItemId finished with status $jobStatus. $(ConvertTo-Json -InputObject $reason -Depth 4 -Compress)"
        }
        return $job
    }
