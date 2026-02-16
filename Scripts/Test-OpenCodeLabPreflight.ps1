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
$subnetConflictHelperPath = Join-Path $RepoRoot 'Private\Test-LabVirtualSwitchSubnetConflict.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $subnetConflictHelperPath) { . $subnetConflictHelperPath }

# Defaults in case Lab-Config.ps1 is absent
if (-not (Get-Variable -Name LabSourcesRoot -ErrorAction SilentlyContinue)) { $GlobalLabConfig.Paths.LabSourcesRoot = 'C:\LabSources' }
if (-not (Get-Variable -Name LabSwitch -ErrorAction SilentlyContinue))      { $GlobalLabConfig.Network.SwitchName = 'AutomatedLab' }
if (-not (Get-Variable -Name NatName -ErrorAction SilentlyContinue))        { $GlobalLabConfig.Network.NatName = 'AutomatedLabNAT' }
if (-not (Get-Variable -Name AddressSpace -ErrorAction SilentlyContinue))   { $GlobalLabConfig.Network.AddressSpace = '10.0.10.0/24' }
if (-not (Get-Variable -Name RequiredISOs -ErrorAction SilentlyContinue))   { @($GlobalLabConfig.RequiredISOs) = @('server2019.iso', 'win11.iso') }

$IsoPath = Join-Path $GlobalLabConfig.Paths.LabSourcesRoot 'ISOs'
$requiredIsoList = @(@($GlobalLabConfig.RequiredISOs))
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
    Write-Host "  Mode: WINDOWS CORE (dc1 + svr1 + dsc + ws1)" -ForegroundColor Yellow
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

try {
    if (Get-Command -Name 'Test-LabVirtualSwitchSubnetConflict' -ErrorAction SilentlyContinue) {
        $subnetConflict = Test-LabVirtualSwitchSubnetConflict -SwitchName $GlobalLabConfig.Network.SwitchName -AddressSpace $GlobalLabConfig.Network.AddressSpace
        if ($subnetConflict.HasConflict) {
            $conflictSummary = @(
                $subnetConflict.ConflictingAdapters |
                    ForEach-Object { "$($_.InterfaceAlias) [$($_.IPAddress)]" }
            )
            Write-Warning "Conflicting vEthernet subnet assignments detected for $($GlobalLabConfig.Network.AddressSpace): $($conflictSummary -join '; '). Deploy preflight can auto-fix these conflicts when you continue with deployment."
        }
        else {
            Add-Ok "No conflicting vEthernet adapters found for subnet $GlobalLabConfig.Network.AddressSpace"
        }
    }
    else {
        Write-Warning 'Subnet conflict helper not available; skipping vEthernet subnet conflict preflight check.'
    }
} catch {
    Add-Issue "Failed vEthernet subnet conflict check: $($_.Exception.Message)"
}

$switch = Get-VMSwitch -Name $GlobalLabConfig.Network.SwitchName -ErrorAction SilentlyContinue
if ($switch) {
    Add-Ok "Switch exists: $GlobalLabConfig.Network.SwitchName"
} else {
    Write-Warning "Switch not found yet: $GlobalLabConfig.Network.SwitchName (bootstrap can create it)"
}

$nat = Get-NetNat -Name $GlobalLabConfig.Network.NatName -ErrorAction SilentlyContinue
if ($nat) {
    Add-Ok "NAT exists: $GlobalLabConfig.Network.NatName"
} else {
    Write-Warning "NAT not found yet: $GlobalLabConfig.Network.NatName (bootstrap can create it)"
}

$sshKey = Join-Path $GlobalLabConfig.Paths.LabSourcesRoot 'SSHKeys\id_ed25519'
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
