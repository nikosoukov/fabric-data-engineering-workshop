#requires -Version 7.0
<#
.SYNOPSIS
    Connects the Dev workspace to GitHub, commits the items, and creates a Fabric deployment pipeline (Dev, Test, Prod).
.DESCRIPTION
    1. Creates a GitHub credential connection (Fabric Connections API) if one is not stored in the state file.
       The token is read from the GITHUB_PAT environment variable, or from `gh auth token` when gh is installed.
       The token is never written to disk. Only the connection ID is stored.
    2. Connects the Dev workspace to git.repo/branch in the folder /fabric-workspace and commits pending changes.
    3. Creates the deployment pipeline and assigns the Dev, Test, and Prod workspaces.
    4. Deploys Dev to Test. Pass -DeployToProd to also promote Test to Prod.
#>
[CmdletBinding()]
param(
    [switch]$DeployToProd
)

. "$PSScriptRoot/common.ps1"
$s = Get-WorkshopSettings
$state = Get-WorkshopState
$ws = $state.fabric.workspaces.dev

Write-Step "GitHub credential connection"
if (-not $state.ContainsKey('gitConnectionId')) {
    $pat = $env:GITHUB_PAT
    if (-not $pat -and (Get-Command gh -ErrorAction SilentlyContinue)) { $pat = (gh auth token 2>$null).Trim() }
    if (-not $pat) { throw 'Set GITHUB_PAT (a token with repo scope) or sign in with gh auth login.' }
    $connBody = @{
        connectivityType  = 'ShareableCloud'
        displayName       = "github-$($s.git.repo)-workshop"
        connectionDetails = @{ type = 'GitHubSourceControl'; creationMethod = 'GitHubSourceControl.Contents' }
        credentialDetails = @{ credentials = @{ credentialType = 'Key'; key = $pat } }
    }
    $conn = Invoke-FabricApi -Method POST -Path '/connections' -Body $connBody
    $pat = $null
    $state = Get-WorkshopState
    $state['gitConnectionId'] = $conn.id
    Set-WorkshopState -State $state
    Write-Host "  created connection $($conn.id)"
}
else { Write-Host "  using stored connection $($state.gitConnectionId)" }

Write-Step "Connecting Dev workspace to git.$($s.git.owner)/$($s.git.repo) ($($s.git.branch), /fabric-workspace)"
$gitStatus = $null
try { $gitStatus = Invoke-FabricApi -Method GET -Path "/workspaces/$ws/git/connection" } catch { }
if (-not $gitStatus) {
    $connectBody = @{
        gitProviderDetails = @{
            gitProviderType = 'GitHub'
            ownerName       = $s.git.owner
            repositoryName  = $s.git.repo
            branchName      = $s.git.branch
            directoryName   = '/fabric-workspace'
        }
        myGitCredentials   = @{ source = 'ConfiguredConnection'; connectionId = $state.gitConnectionId }
    }
    Invoke-FabricApi -Method POST -Path "/workspaces/$ws/git/connect" -Body $connectBody | Out-Null
    Write-Host "  connected"
}
try {
    Invoke-FabricApi -Method POST -Path "/workspaces/$ws/git/initializeConnection" -Body @{ initializationStrategy = 'PreferWorkspace' } | Out-Null
}
catch {
    # 409 means the connection was already initialized, which is expected on re-runs.
    if ($_.Exception.Message -notmatch 'WorkspaceGitConnectionAlreadyInitialized') { throw }
}
$status = Invoke-FabricApi -Method GET -Path "/workspaces/$ws/git/status"
$changes = @($status.changes).Count
if ($changes -gt 0) {
    Invoke-FabricApi -Method POST -Path "/workspaces/$ws/git/commitToGit" -Body @{ mode = 'All'; workspaceHead = $status.workspaceHead; comment = 'Sync FDW Dev workspace items' } | Out-Null
    Write-Host "  committed $changes change(s)"
}
else { Write-Host "  no pending changes" }

Write-Step "Creating deployment pipeline dp_fdw_osfi"
$dpName = 'dp_fdw_osfi'
$dp = Get-FabricList -Path '/deploymentPipelines' | Where-Object { $_.displayName -eq $dpName } | Select-Object -First 1
if (-not $dp) {
    $dp = Invoke-FabricApi -Method POST -Path '/deploymentPipelines' -Body @{
        displayName = $dpName
        description = 'Dev to Test to Prod for the Fabric data engineering workshop'
        stages      = @(
            @{ displayName = 'Development'; description = 'FDW Dev workspace (Git-connected)' },
            @{ displayName = 'Test';        description = 'FDW Test workspace' },
            @{ displayName = 'Production';  description = 'FDW Prod workspace' }
        )
    }
}
$dpId = $dp.id
$stages = (Invoke-FabricApi -Method GET -Path "/deploymentPipelines/$dpId/stages").value
$stageByName = @{}
foreach ($stage in $stages) { $stageByName[$stage.displayName.ToLower()] = $stage }
$assign = @{ dev = $ws; test = $state.fabric.workspaces.test; prod = $state.fabric.workspaces.prod }
foreach ($key in @('dev', 'test', 'prod')) {
    $stageName = @{ dev = 'development'; test = 'test'; prod = 'production' }[$key]
    $stage = $stageByName[$stageName]
    if (-not $stage) { $stage = $stages | Where-Object { $_.displayName -like "*$($key.Substring(0,3))*" } | Select-Object -First 1 }
    if ((Get-OptionalProperty -Object $stage -Name 'workspaceId') -ne $assign[$key]) {
        Invoke-FabricApi -Method POST -Path "/deploymentPipelines/$dpId/stages/$($stage.id)/assignWorkspace" -Body @{ workspaceId = $assign[$key] } | Out-Null
        Write-Host "  assigned $key workspace to stage $($stage.displayName)"
    }
}
$stages = (Invoke-FabricApi -Method GET -Path "/deploymentPipelines/$dpId/stages").value
$devStage = $stages | Sort-Object order | Select-Object -First 1
$testStage = $stages | Sort-Object order | Select-Object -Skip 1 -First 1
$prodStage = $stages | Sort-Object order | Select-Object -Skip 2 -First 1

Write-Step "Deploying Dev to Test"
$testWs = $state.fabric.workspaces.test
$testHasLakehouse = @(Get-FabricList -Path "/workspaces/$testWs/items?type=Lakehouse").Count -gt 0
$devItems = @()
foreach ($t in 'Notebook', 'DataPipeline', 'Dataflow') {
    foreach ($i in (Get-FabricList -Path "/workspaces/$ws/items?type=$t")) { $devItems += @{ sourceItemId = $i.id; itemType = $t } }
}
$deployBody = @{
    sourceStageId = $devStage.id
    targetStageId = $testStage.id
    options       = @{ allowCreateArtifact = $true; allowOverwriteArtifact = $true }
}
if ($testHasLakehouse) {
    # Re-deploy: send code items only. A warehouse that already exists in the target fails a repeat copy in
    # the deployment pipeline (CopyOverwriteResult.GenericError). Apply warehouse DDL with scripts/05 instead.
    $deployBody.items = $devItems
    Write-Host "  selective deploy: notebooks, pipelines, dataflows"
}
else {
    Write-Host "  first deploy: all items"
}
Invoke-FabricApi -Method POST -Path "/deploymentPipelines/$dpId/deploy" -Body $deployBody | Out-Null
Write-Host "  Dev to Test deployed"

if ($DeployToProd) {
    Write-Step "Deploying Test to Prod"
    $prodWs = $state.fabric.workspaces.prod
    $prodHasLakehouse = @(Get-FabricList -Path "/workspaces/$prodWs/items?type=Lakehouse").Count -gt 0
    $testItems = @()
    foreach ($t in 'Notebook', 'DataPipeline', 'Dataflow') {
        foreach ($i in (Get-FabricList -Path "/workspaces/$testWs/items?type=$t")) { $testItems += @{ sourceItemId = $i.id; itemType = $t } }
    }
    $prodBody = @{
        sourceStageId = $testStage.id
        targetStageId = $prodStage.id
        options       = @{ allowCreateArtifact = $true; allowOverwriteArtifact = $true }
    }
    if ($prodHasLakehouse) { $prodBody.items = $testItems; Write-Host "  selective deploy: notebooks, pipelines, dataflows" }
    else { Write-Host "  first deploy: all items" }
    Invoke-FabricApi -Method POST -Path "/deploymentPipelines/$dpId/deploy" -Body $prodBody | Out-Null
    Write-Host "  Test to Prod deployed"
}

$state = Get-WorkshopState
$state['deploymentPipelineId'] = $dpId
Set-WorkshopState -State $state
