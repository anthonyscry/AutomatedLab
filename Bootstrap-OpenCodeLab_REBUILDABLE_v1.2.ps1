<#
.SYNOPSIS
    Bootstrap-OpenCodeLab.ps1 — One-click setup for AutomatedLab + OpenCode Dev Lab

.DESCRIPTION
    Run this once. It handles everything:
      1. NuGet provider
      2. Pester publisher conflict fix
      3. PSFramework dependency
      4. SHiPS dependency
      5. AutomatedLab module install
      6. LabSources folder creation
      7. Hyper-V checks
      8. Lab vSwitch + NAT setup (recommended)
      9. ISO validation
     10. Kicks off Deploy script
      8. ISO validation
      9. Kicks off Deploy-OpenCodeLab-Slim.ps1

    After this completes, your lab is ready.

.NOTES
    Author:  Tony / Claude
    Version: 1.1
    Run as:  Administrator (required)
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Speeds up downloads

# ── Config ──
$LabSourcesRoot = 'C:\LabSources'
$ISOPath        = "$LabSourcesRoot\ISOs"
$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DeployScript   = (Join-Path $ScriptDir 'Deploy-OpenCodeLab-Slim_REBUILDABLE_v3.2.ps1')
if (-not (Test-Path $DeployScript)) { $DeployScript = (Join-Path $ScriptDir 'Deploy-OpenCodeLab-Slim_FIXED_FINAL.ps1') }
if (-not (Test-Path $DeployScript)) { $DeployScript = Join-Path $ScriptDir 'Deploy-OpenCodeLab-Slim_FIXED_FINAL.ps1' }
if (-not (Test-Path $DeployScript)) { $DeployScript = Join-Path $ScriptDir 'Deploy-OpenCodeLab-Slim_FIXED.ps1' }
if (-not (Test-Path $DeployScript)) { $DeployScript = Join-Path $ScriptDir 'Deploy-OpenCodeLab-Slim.ps1' }

$RequiredISOs = @(
    'server2019.iso',
    'win11.iso',
    'ubuntu-24.04.3.iso'
)

$RequiredFolders = @(
    $LabSourcesRoot,
    "$LabSourcesRoot\ISOs",
    "$LabSourcesRoot\SoftwarePackages",
    "$LabSourcesRoot\PostInstallationActivities",
    "$LabSourcesRoot\Tools",
    "$LabSourcesRoot\SSHKeys",
    "$LabSourcesRoot\Logs"
)

# ── Functions ──
function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "`n[$Step] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "  [SKIP] $Message" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

# ============================================================
# STEP 1: NuGet Provider
# ============================================================
Write-Step "1/10" "NuGet provider"

$nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if (-not $nuget -or $nuget.Version -lt [version]'2.8.5.201') {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Write-OK "NuGet provider installed"
} else {
    Write-Skip "NuGet provider already installed (v$($nuget.Version))"
}

# ============================================================
# STEP 2: Fix Pester publisher conflict
# ============================================================
Write-Step "2/10" "Pester module (fixing publisher conflict)"

$pester = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester -or $pester.Version -lt [version]'5.0.0') {
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope AllUsers
    Write-OK "Pester updated to latest"
} else {
    Write-Skip "Pester already v$($pester.Version)"
}

# ============================================================
# STEP 3: PSFramework
# ============================================================
Write-Step "3/10" "PSFramework module"

if (-not (Get-Module -Name PSFramework -ListAvailable)) {
    Install-Module -Name PSFramework -Force -Scope AllUsers
    Write-OK "PSFramework installed"
} else {
    Write-Skip "PSFramework already installed"
}

# ============================================================
# STEP 4: SHiPS (required for AutomatedLab.Ships)
# ============================================================
Write-Step "4/10" "SHiPS module"

if (-not (Get-Module -Name SHiPS -ListAvailable)) {
    Install-Module -Name SHiPS -Force -Scope AllUsers
    Write-OK "SHiPS installed"
} else {
    Write-Skip "SHiPS already installed"
}

# ============================================================
# STEP 5: AutomatedLab
# ============================================================
Write-Step "5/10" "AutomatedLab module"

$al = Get-Module -Name AutomatedLab -ListAvailable
if (-not $al) {
    Install-Module -Name AutomatedLab -AllowClobber -Force -SkipPublisherCheck -Scope AllUsers
    Write-OK "AutomatedLab installed"
} else {
    Write-Skip "AutomatedLab already installed (v$(($al | Select-Object -First 1).Version))"
}

# Import it now so we can use its cmdlets
Import-Module AutomatedLab -ErrorAction SilentlyContinue

# ============================================================
# STEP 6: LabSources folder structure
# ============================================================
Write-Step "6/10" "LabSources folder structure"

foreach ($folder in $RequiredFolders) {
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Write-OK "Created $folder"
    } else {
        Write-Skip "$folder exists"
    }
}

# Try official LabSources download (non-fatal if it fails)
try {
    if (Get-Command New-LabSourcesFolder -ErrorAction SilentlyContinue) {
        New-LabSourcesFolder -Force -ErrorAction Stop
        Write-OK "LabSources populated from GitHub"
    }
} catch {
    Write-Warn "GitHub download failed (non-fatal). Manual folders are sufficient."
}

# ============================================================
# STEP 7: Hyper-V check
# ============================================================
Write-Step "7/10" "Hyper-V role"

$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
if ($hyperv.State -eq 'Enabled') {
    Write-OK "Hyper-V is enabled"
} else {
    Write-Warn "Hyper-V is not enabled. Attempting to enable..."
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart -ErrorAction Stop | Out-Null
        Write-OK "Hyper-V enabled. A REBOOT IS REQUIRED before deploying the lab."
        Write-Host "`n  Reboot your machine, then re-run this script." -ForegroundColor Yellow
        if (-not $NonInteractive) {
            Read-Host "  Press Enter to exit"
        }
        exit 3010
    } catch {
        Write-Fail "Could not enable Hyper-V: $($_.Exception.Message)"
        Write-Host "  Enable it manually: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All" -ForegroundColor Yellow
        exit 1
    }
}

# ============================================================
# STEP 8: Lab vSwitch + NAT (recommended)
# ============================================================
Write-Step "8/10" "Lab vSwitch + NAT (recommended)"

# NOTE: Hyper-V "Default Switch" is not reliable for AutomatedLab (NAT/DHCP subnet is managed by Windows and may change).
# Use a dedicated Internal vSwitch + host NAT instead.

$LabSwitch    = 'OpenCodeLabSwitch'
$AddressSpace = '192.168.11.0/24'
$GatewayIp    = '192.168.11.1'
$NatName      = "${LabSwitch}NAT"

try {
    # Create/reuse internal vSwitch
    $sw = Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue
    if (-not $sw) {
        New-VMSwitch -Name $LabSwitch -SwitchType Internal | Out-Null
        Write-OK "Created Hyper-V vSwitch: $LabSwitch (Internal)"
    } else {
        Write-Skip "vSwitch exists: $LabSwitch"
    }

    # Assign host vNIC IP (gateway)
    $ifAlias = "vEthernet ($LabSwitch)"
    $ip = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -eq $GatewayIp }

    if (-not $ip) {
        # Remove any old IPv4 addresses on that vNIC (optional, but helps avoid conflicts)
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
        Write-OK "Assigned host gateway IP: $GatewayIp on $ifAlias"
    } else {
        Write-Skip "Host gateway IP already set: $GatewayIp on $ifAlias"
    }

    # Create/reuse NAT
    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-OK "Created NAT: $NatName for $AddressSpace"
    } else {
        Write-Skip "NAT exists: $NatName"
    }

} catch {
    Write-Warn "Could not create vSwitch/NAT automatically: $($_.Exception.Message)"
    Write-Host "  You can still continue, but deployment may fail if the lab uses 'Default Switch'." -ForegroundColor Yellow
    Write-Host "  Recommended manual commands:" -ForegroundColor Yellow
    Write-Host "    New-VMSwitch -Name $LabSwitch -SwitchType Internal" -ForegroundColor Yellow
    Write-Host "    New-NetIPAddress -InterfaceAlias 'vEthernet ($LabSwitch)' -IPAddress $GatewayIp -PrefixLength 24" -ForegroundColor Yellow
    Write-Host "    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace" -ForegroundColor Yellow
    if (-not $NonInteractive) {
        Read-Host "  Press Enter to continue anyway, or Ctrl+C to abort"
    }
}

# ============================================================
# STEP 9: ISO validation
# ============================================================
Write-Step "9/10" "ISO files in $ISOPath"

$allISOsFound = $true
foreach ($iso in $RequiredISOs) {
    $isoFullPath = Join-Path $ISOPath $iso
    if (Test-Path $isoFullPath) {
        $sizeMB = [math]::Round((Get-Item $isoFullPath).Length / 1MB)
        Write-OK "$iso ($sizeMB MB)"
    } else {
        Write-Fail "$iso NOT FOUND"
        $allISOsFound = $false
    }
}

if (-not $allISOsFound) {
    Write-Host "`n  Missing ISOs. Place them in $ISOPath and re-run." -ForegroundColor Red
    Write-Host "  Required files:" -ForegroundColor Yellow
    foreach ($iso in $RequiredISOs) { Write-Host "    - $iso" -ForegroundColor Yellow }
    if (-not $NonInteractive) {
        Read-Host "`n  Press Enter to exit"
    }
    exit 1
}

# Verify AutomatedLab can read them
Write-Host "`n  Verifying AutomatedLab can detect the ISOs..." -ForegroundColor Gray
try {
    $detectedOS = Get-LabAvailableOperatingSystem -Path $ISOPath -ErrorAction Stop
    if ($detectedOS) {
        foreach ($os in $detectedOS) {
            Write-OK "Detected: $($os.OperatingSystemName)"
        }
    } else {
        Write-Warn "No operating systems detected. ISOs may be corrupt."
    }
} catch {
    Write-Warn "Could not verify ISOs: $($_.Exception.Message)"
}

# ============================================================
# STEP 10: Deploy
# ============================================================
Write-Step "10/10" "Launching lab deployment"

if ($SkipDeploy) {
    Write-Skip "Skipping deploy step because -SkipDeploy was supplied"
    exit 0
}

if (Test-Path $DeployScript) {
    Write-Host "`n  All prerequisites met. Starting deployment..." -ForegroundColor Green
    Write-Host "  Script: $DeployScript" -ForegroundColor Gray
    Write-Host "  This will take 30-60 minutes on first run.`n" -ForegroundColor Gray
    if ($NonInteractive) {
        & $DeployScript -NonInteractive
    } else {
        & $DeployScript
    }
} else {
    Write-Fail "Deploy script not found at: $DeployScript"
    Write-Host "  Make sure Deploy-OpenCodeLab-Slim.ps1 is in the same folder as this script." -ForegroundColor Yellow
    Write-Host "  Expected location: $DeployScript" -ForegroundColor Yellow
    exit 1
}

