[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$NoLaunch,
    [switch]$GUI,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-OpenCodeLabBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    Write-Host '[OpenCodeLab] Building project...' -ForegroundColor Cyan
    & dotnet build $ProjectPath
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for project: $ProjectPath"
    }
}

function Start-OpenCodeLabApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        [string[]]$Arguments
    )

    Write-Host '[OpenCodeLab] Launching app...' -ForegroundColor Cyan

    $runArgs = @('run', '--project', $ProjectPath)
    if ($Arguments -and $Arguments.Count -gt 0) {
        $runArgs += '--'
        $runArgs += $Arguments
    }

    & dotnet @runArgs
}

function Show-LauncherMenu {
    Write-Host ''
    Write-Host 'OpenCodeLab Launcher' -ForegroundColor Green
    Write-Host '1) Launch desktop app' -ForegroundColor Yellow
    Write-Host '2) Build only' -ForegroundColor Yellow
    Write-Host '3) Quit' -ForegroundColor Yellow
    Write-Host ''

    $choice = Read-Host 'Select an option [1-3]'
    switch ($choice) {
        '1' { return 'launch' }
        '2' { return 'build-only' }
        default { return 'quit' }
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptDir
$projectPath = Join-Path $repoRoot 'OpenCodeLab-v2/OpenCodeLab-V2.csproj'

if (-not (Test-Path -Path $projectPath -PathType Leaf)) {
    throw "Required project file not found: $projectPath"
}

$effectiveArguments = @($AppArguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$menuMode = ($effectiveArguments.Count -eq 0)

if ($NoLaunch) {
    if (-not $SkipBuild) {
        Invoke-OpenCodeLabBuild -ProjectPath $projectPath
    }
    return
}

if ($menuMode) {
    $menuAction = Show-LauncherMenu
    if ($menuAction -eq 'quit') {
        return
    }
    if ($menuAction -eq 'build-only') {
        Invoke-OpenCodeLabBuild -ProjectPath $projectPath
        Write-Host '[OpenCodeLab] Build complete.' -ForegroundColor Green
        return
    }
}

if (-not $SkipBuild) {
    Invoke-OpenCodeLabBuild -ProjectPath $projectPath
}

if ($GUI) {
    Start-OpenCodeLabApp -ProjectPath $projectPath -Arguments @()
    return
}

Start-OpenCodeLabApp -ProjectPath $projectPath -Arguments $effectiveArguments
