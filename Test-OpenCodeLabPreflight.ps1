# Test-OpenCodeLabPreflight.ps1 - validates host readiness for OpenCodeLab deployment

#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LabSourcesRoot = 'C:\LabSources'
$IsoPath = Join-Path $LabSourcesRoot 'ISOs'
$RequiredISOs = @('server2019.iso', 'win11.iso', 'ubuntu-24.04.3.iso')
$LabSwitch = 'OpenCodeLabSwitch'
$NatName = 'OpenCodeLabSwitchNAT'

$issues = @()

function Add-Issue {
    param([Parameter(Mandatory)][string]$Message)
    $script:issues += $Message
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Add-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

Write-Host "`n=== OPENCODELAB PREFLIGHT ===" -ForegroundColor Cyan

try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-Ok 'Running elevated'
    } else {
        Add-Issue 'PowerShell is not running as Administrator'
    }
} catch {
    Add-Issue "Could not validate elevation: $($_.Exception.Message)"
}

try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction Stop
    if ($feature.State -eq 'Enabled') {
        Add-Ok 'Hyper-V is enabled'
    } else {
        Add-Issue 'Hyper-V is not enabled'
    }
} catch {
    Add-Issue "Could not query Hyper-V feature: $($_.Exception.Message)"
}

if (Get-Module -ListAvailable -Name AutomatedLab) {
    Add-Ok 'AutomatedLab module is installed'
} else {
    Add-Issue 'AutomatedLab module not found'
}

if (Test-Path $IsoPath) {
    Add-Ok "ISO folder exists: $IsoPath"
} else {
    Add-Issue "ISO folder missing: $IsoPath"
}

foreach ($iso in $RequiredISOs) {
    $p = Join-Path $IsoPath $iso
    if (Test-Path $p) {
        Add-Ok "Found ISO: $iso"
    } else {
        Add-Issue "Missing ISO: $iso"
    }
}

$switch = Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue
if ($switch) {
    Add-Ok "Switch exists: $LabSwitch"
} else {
    Write-Host "  [WARN] Switch not found yet: $LabSwitch (bootstrap can create it)" -ForegroundColor Yellow
}

$nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if ($nat) {
    Add-Ok "NAT exists: $NatName"
} else {
    Write-Host "  [WARN] NAT not found yet: $NatName (bootstrap can create it)" -ForegroundColor Yellow
}

$sshKey = Join-Path $LabSourcesRoot 'SSHKeys\id_ed25519'
$sshPub = "$sshKey.pub"
if ((Test-Path $sshKey) -and (Test-Path $sshPub)) {
    Add-Ok 'Host SSH keypair exists (id_ed25519)'
} else {
    Write-Host '  [WARN] Host SSH keypair missing (deploy will generate it)' -ForegroundColor Yellow
}

if ($issues.Count -gt 0) {
    Write-Host "`nPreflight failed with $($issues.Count) blocking issue(s)." -ForegroundColor Red
    exit 1
}

Write-Host "`nPreflight passed." -ForegroundColor Green
