<#
.SYNOPSIS
    Test-OpenCodeLabHealth.ps1 - strict post-deploy health gate for OpenCodeLab
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LabName = 'OpenCodeLab'
$ExpectedVMs = @('DC1', 'WS1', 'LIN1')
$DomainName = 'opencode.lab'
$LinuxUser = 'install'
$SSHKeyPath = 'C:\LabSources\SSHKeys\id_ed25519'
$Lin1Ip = '192.168.11.5'
$issues = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([Parameter(Mandatory)][string]$Message)
    $script:issues.Add($Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Add-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

Write-Host "`n=== OPENCODELAB HEALTH GATE ===" -ForegroundColor Cyan

try {
    Import-Module AutomatedLab -ErrorAction Stop | Out-Null
    Import-Lab -Name $LabName -ErrorAction Stop | Out-Null
    Add-Ok "Imported lab '$LabName'"
} catch {
    Add-Issue "Unable to import lab '$LabName': $($_.Exception.Message)"
}

foreach ($vmName in $ExpectedVMs) {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Add-Issue "VM '$vmName' not found"
        continue
    }
    if ($vm.State -ne 'Running') {
        Add-Issue "VM '$vmName' is not running (state: $($vm.State))"
    } else {
        Add-Ok "VM '$vmName' running"
    }
}

if (-not $issues.Count) {
    try {
        $dcChecks = Invoke-LabCommand -ComputerName 'DC1' -PassThru -ScriptBlock {
            $result = @{}
            $result.NTDS = (Get-Service NTDS -ErrorAction SilentlyContinue).Status
            $result.DNS = (Get-Service DNS -ErrorAction SilentlyContinue).Status
            $result.SSHD = (Get-Service sshd -ErrorAction SilentlyContinue).Status
            $result.Share = [bool](Get-SmbShare -Name 'LabShare' -ErrorAction SilentlyContinue)
            $result
        }

        if ($dcChecks.NTDS -eq 'Running') { Add-Ok 'DC1 NTDS running' } else { Add-Issue 'DC1 NTDS not running' }
        if ($dcChecks.DNS -eq 'Running') { Add-Ok 'DC1 DNS running' } else { Add-Issue 'DC1 DNS not running' }
        if ($dcChecks.SSHD -eq 'Running') { Add-Ok 'DC1 sshd running' } else { Add-Issue 'DC1 sshd not running' }
        if ($dcChecks.Share) { Add-Ok 'DC1 LabShare present' } else { Add-Issue 'DC1 LabShare missing' }
    } catch {
        Add-Issue "DC1 health checks failed: $($_.Exception.Message)"
    }

    try {
        $wsChecks = Invoke-LabCommand -ComputerName 'WS1' -PassThru -ScriptBlock {
            $result = @{}
            $result.AppIDSvc = (Get-Service AppIDSvc -ErrorAction SilentlyContinue).Status
            $result.LDrive = Test-Path 'L:\'
            $cs = Get-CimInstance Win32_ComputerSystem
            $result.PartOfDomain = [bool]$cs.PartOfDomain
            $result.Domain = $cs.Domain
            $dns = Resolve-DnsName -Name 'dc1.opencode.lab' -ErrorAction SilentlyContinue
            $result.DnsOk = [bool]$dns
            $result
        }

        if ($wsChecks.AppIDSvc -eq 'Running') { Add-Ok 'WS1 AppIDSvc running' } else { Add-Issue 'WS1 AppIDSvc not running' }
        if ($wsChecks.LDrive) { Add-Ok 'WS1 L: mapped' } else { Add-Issue 'WS1 L: not mapped' }
        if ($wsChecks.PartOfDomain -and $wsChecks.Domain -ieq $DomainName) { Add-Ok 'WS1 domain join healthy' } else { Add-Issue "WS1 domain join invalid ($($wsChecks.Domain))" }
        if ($wsChecks.DnsOk) { Add-Ok 'WS1 DNS resolution works for DC1' } else { Add-Issue 'WS1 DNS resolution for DC1 failed' }
    } catch {
        Add-Issue "WS1 health checks failed: $($_.Exception.Message)"
    }

    try {
        $linChecks = Invoke-LabCommand -ComputerName 'LIN1' -PassThru -ScriptBlock {
            $result = @{}
            $mountState = bash -lc 'if mountpoint -q /mnt/labshare; then echo yes; else echo no; fi'
            $result.Mounted = (($mountState | Select-Object -First 1).ToString().Trim() -eq 'yes')
            $dnsState = bash -lc 'if getent hosts dc1.opencode.lab >/dev/null 2>&1; then echo yes; else echo no; fi'
            $result.DnsOk = (($dnsState | Select-Object -First 1).ToString().Trim() -eq 'yes')
            $result
        }

        if ($linChecks.Mounted) { Add-Ok 'LIN1 /mnt/labshare mounted' } else { Add-Issue 'LIN1 /mnt/labshare not mounted' }
        if ($linChecks.DnsOk) { Add-Ok 'LIN1 DNS resolution works for DC1' } else { Add-Issue 'LIN1 DNS resolution for DC1 failed' }
    } catch {
        Add-Issue "LIN1 health checks failed: $($_.Exception.Message)"
    }

    try {
        if (-not (Test-Path $SSHKeyPath)) {
            Add-Issue "Host SSH key missing: $SSHKeyPath"
        } else {
            $sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
            if (-not (Test-Path $sshExe)) {
                Add-Issue 'Host OpenSSH client (ssh.exe) not found'
            } else {
                $sshOut = & $sshExe -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -i $SSHKeyPath "$LinuxUser@$Lin1Ip" 'echo ok' 2>&1
                if ($LASTEXITCODE -eq 0 -and ($sshOut | Out-String) -match 'ok') {
                    Add-Ok 'Host SSH to LIN1 verified'
                } else {
                    Add-Issue 'Host SSH to LIN1 failed'
                }
            }
        }
    } catch {
        Add-Issue "Host SSH check failed: $($_.Exception.Message)"
    }
}

if ($issues.Count -gt 0) {
    throw "Health gate failed with $($issues.Count) issue(s)."
}

Write-Host "`nHealth gate passed." -ForegroundColor Green
