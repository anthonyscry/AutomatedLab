#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install AutomatedLab module from bundled modules (airgapped/offline).

.DESCRIPTION
    Copies pre-bundled AutomatedLab modules from LabSources\Modules\ into
    the system PowerShell modules directory. Designed for airgapped servers
    with no internet access.

    To create the bundle on a connected machine:
      Save-Module AutomatedLab -Path LabSources\Modules\ -Repository PSGallery
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== AutomatedLab Setup ===" -ForegroundColor Cyan

# Check if already installed
$existing = Get-Module AutomatedLab -ListAvailable -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[OK] AutomatedLab v$($existing.Version) is already installed at:" -ForegroundColor Green
    Write-Host "     $($existing.ModuleBase)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To reinstall, run: Uninstall-Module AutomatedLab -AllVersions" -ForegroundColor Yellow
    exit 0
}

# Locate bundled modules
$bundledModules = Join-Path $PSScriptRoot "LabSources\Modules"
if (-not (Test-Path $bundledModules)) {
    Write-Host "[ERROR] Bundled modules not found at:" -ForegroundColor Red
    Write-Host "        $bundledModules" -ForegroundColor Red
    Write-Host ""
    Write-Host "To create the bundle, run on a connected machine:" -ForegroundColor Yellow
    Write-Host "  Save-Module AutomatedLab -Path LabSources\Modules\" -ForegroundColor Yellow
    exit 1
}

$moduleNames = Get-ChildItem $bundledModules -Directory | Select-Object -ExpandProperty Name
if ($moduleNames.Count -eq 0) {
    Write-Host "[ERROR] No modules found in $bundledModules" -ForegroundColor Red
    Write-Host ""
    Write-Host "To create the bundle, run on a connected machine:" -ForegroundColor Yellow
    Write-Host "  Save-Module AutomatedLab -Path LabSources\Modules\" -ForegroundColor Yellow
    exit 1
}

# Copy modules to system path
Write-Host "Installing from bundled modules..." -ForegroundColor Yellow
$targetPath = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules"

foreach ($mod in $moduleNames) {
    $src = Join-Path $bundledModules $mod
    $dst = Join-Path $targetPath $mod
    if (Test-Path $dst) {
        Write-Host "  [SKIP] $mod (already exists)" -ForegroundColor DarkGray
    } else {
        Write-Host "  [COPY] $mod -> $dst" -ForegroundColor Cyan
        Copy-Item $src $dst -Recurse -Force
    }
}

# Create LabSources if needed
$labSourcesPath = "C:\LabSources"
if (-not (Test-Path $labSourcesPath)) {
    Write-Host ""
    Write-Host "Creating LabSources folder structure at $labSourcesPath..." -ForegroundColor Yellow
    New-LabSourcesFolder -DriveLetter C -ErrorAction SilentlyContinue
    if (-not (Test-Path $labSourcesPath)) {
        $dirs = @('ISOs', 'VMs', 'Logs', 'LabConfig', 'CustomRoles', 'Tools',
                  'PostInstallationActivities', 'SoftwarePackages', 'SampleScripts',
                  'SSHKeys', 'OSUpdates')
        foreach ($d in $dirs) {
            New-Item -Path (Join-Path $labSourcesPath $d) -ItemType Directory -Force | Out-Null
        }
    }
    Write-Host "[OK] LabSources created at $labSourcesPath" -ForegroundColor Green
}

# Verify
$installed = Get-Module AutomatedLab -ListAvailable
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "AutomatedLab v$($installed.Version) ready" -ForegroundColor Green
Write-Host "Module path: $($installed.ModuleBase)" -ForegroundColor Gray
Write-Host "LabSources:  $labSourcesPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Place ISOs in $labSourcesPath\ISOs\" -ForegroundColor Gray
Write-Host "  2. Run OpenCodeLab-V2.exe" -ForegroundColor Gray
