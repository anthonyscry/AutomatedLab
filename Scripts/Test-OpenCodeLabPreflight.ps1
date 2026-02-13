# Test-OpenCodeLabPreflight.ps1 - validates host readiness for OpenCodeLab deployment

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$IncludeLIN1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $RepoRoot 'Lab-Config.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }

# Defaults in case Lab-Config.ps1 is absent
if (-not (Get-Variable -Name LabSourcesRoot -ErrorAction SilentlyContinue)) { $LabSourcesRoot = 'C:\LabSources' }
if (-not (Get-Variable -Name LabSwitch -ErrorAction SilentlyContinue))      { $LabSwitch = 'OpenCodeLabSwitch' }
if (-not (Get-Variable -Name NatName -ErrorAction SilentlyContinue))        { $NatName = 'OpenCodeLabSwitchNAT' }
if (-not (Get-Variable -Name RequiredISOs -ErrorAction SilentlyContinue))   { $RequiredISOs = @('server2019.iso', 'win11.iso') }

$IsoPath = Join-Path $LabSourcesRoot 'ISOs'
$requiredIsoList = @($RequiredISOs)
if ($IncludeLIN1) {
    if (-not ($requiredIsoList -contains 'ubuntu-24.04.3.iso')) {
        $requiredIsoList += 'ubuntu-24.04.3.iso'
    }
} else {
    $requiredIsoList = $requiredIsoList | Where-Object { $_ -ne 'ubuntu-24.04.3.iso' }
}

$issues = New-Object System.Collections.Generic.List[string]
. (Join-Path $ScriptDir 'Helpers-TestReport.ps1')

Write-Host "`n=== OPENCODELAB PREFLIGHT ===" -ForegroundColor Cyan
if ($IncludeLIN1) {
    Write-Host "  Mode: FULL (Windows core + optional Ubuntu LIN1)" -ForegroundColor Green
} else {
    Write-Host "  Mode: WINDOWS CORE (DC1 + WSUS1 + WS1)" -ForegroundColor Yellow
}

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

foreach ($iso in $requiredIsoList) {
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
