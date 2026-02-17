#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\LabSources\OfflineBundles',
    [string]$AutomatedLabVersion
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OutputRoot)) {
    $null = New-Item -Path $OutputRoot -ItemType Directory -Force
    Write-Verbose "Created offline bundle output root: $OutputRoot"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bundlePath = Join-Path $OutputRoot ("AutomatedLab-Offline-{0}" -f $stamp)
$modulesPath = Join-Path $bundlePath 'Modules'

$null = New-Item -Path $modulesPath -ItemType Directory -Force
Write-Verbose "Created bundle modules directory: $modulesPath"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
}

Write-Host ''
Write-Host ('[INFO] Building offline bundle at {0}' -f $bundlePath) -ForegroundColor Cyan

$saveParams = @{
    Name = 'AutomatedLab'
    Path = $modulesPath
    Repository = 'PSGallery'
    Force = $true
}

if (-not [string]::IsNullOrWhiteSpace($AutomatedLabVersion)) {
    $saveParams['RequiredVersion'] = $AutomatedLabVersion
}

Save-Module @saveParams

$moduleDirs = Get-ChildItem -Path $modulesPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name

$installScriptPath = Join-Path $bundlePath 'Install-OfflineAutomatedLab.ps1'
$installScript = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$Destination = "$env:ProgramFiles\WindowsPowerShell\Modules"
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'Modules'
if (-not (Test-Path $source)) {
    throw "Modules folder not found: $source"
}

if (-not (Test-Path $Destination)) {
    $null = New-Item -Path $Destination -ItemType Directory -Force
}

Copy-Item -Path (Join-Path $source '*') -Destination $Destination -Recurse -Force

$null = Import-Module AutomatedLab -ErrorAction Stop
$module = Get-Module -ListAvailable -Name AutomatedLab | Sort-Object Version -Descending | Select-Object -First 1

Write-Host ''
Write-Host ('[OK] AutomatedLab offline install complete: {0}' -f $module.Version) -ForegroundColor Green
Write-Host ('[OK] Installed to: {0}' -f $Destination) -ForegroundColor Green
'@
$installScript | Set-Content -Path $installScriptPath -Encoding UTF8

$manifestPath = Join-Path $bundlePath 'bundle-manifest.json'
$manifest = [pscustomobject]@{
    generated_at = (Get-Date).ToString('o')
    bundle_path = $bundlePath
    module_count = $moduleDirs.Count
    modules = @($moduleDirs | ForEach-Object { $_.Name })
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host ('[OK] Offline modules downloaded: {0}' -f $moduleDirs.Count) -ForegroundColor Green
Write-Host ('[OK] Bundle folder: {0}' -f $bundlePath) -ForegroundColor Green
Write-Host ('[OK] Install script: {0}' -f $installScriptPath) -ForegroundColor Green
Write-Host ('[OK] Manifest: {0}' -f $manifestPath) -ForegroundColor Green
