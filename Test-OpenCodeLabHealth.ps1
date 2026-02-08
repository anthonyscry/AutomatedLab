# Test-OpenCodeLabHealth.ps1 - strict post-deploy health gate for OpenCodeLab

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$IncludeLIN1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }

# Defaults (overridden by Lab-Config.ps1 if present)
if (-not (Get-Variable -Name LabName -ErrorAction SilentlyContinue)) { $LabName = 'OpenCodeLab' }
if (-not (Get-Variable -Name LabVMs -ErrorAction SilentlyContinue)) { $LabVMs = @('DC1', 'WS1', 'LIN1') }
if (-not (Get-Variable -Name LinuxUser -ErrorAction SilentlyContinue)) { $LinuxUser = 'anthonyscry' }

$ExpectedVMs = if ($IncludeLIN1) { @($LabVMs) } else { @($LabVMs | Where-Object { $_ -ne 'LIN1' }) }
if (-not (Get-Variable -Name DomainName -ErrorAction SilentlyContinue)) { $DomainName = 'opencode.lab' }
if (-not (Get-Variable -Name LIN1_Ip -ErrorAction SilentlyContinue))   { $LIN1_Ip = '192.168.11.5' }
$SSHKeyPath = Join-Path $LabSourcesRoot 'SSHKeys\id_ed25519'
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

function Invoke-LabStructuredCheck {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$RequiredProperty,
        [int]$Attempts = 3,
        [int]$DelaySeconds = 10
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $raw = @()
            if ($ArgumentList -and $ArgumentList.Count -gt 0) {
                $raw = @(Invoke-LabCommand -ComputerName $ComputerName -PassThru -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList)
            } else {
                $raw = @(Invoke-LabCommand -ComputerName $ComputerName -PassThru -ScriptBlock $ScriptBlock)
            }

            $structured = @($raw | Where-Object { $_ -and ($_.PSObject.Properties.Name -contains $RequiredProperty) } | Select-Object -Last 1)
            if ($structured.Count -gt 0) {
                return $structured[0]
            }
        } catch {
            if ($attempt -ge $Attempts) {
                throw
            }
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return $null
}

Write-Host "`n=== OPENCODELAB HEALTH GATE ===" -ForegroundColor Cyan
if ($IncludeLIN1) {
    Write-Host "  Mode: FULL (LIN1 checks enabled)" -ForegroundColor Green
} else {
    Write-Host "  Mode: CORE (LIN1 checks skipped)" -ForegroundColor Yellow
}

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
        $dcChecks = Invoke-LabStructuredCheck -ComputerName 'DC1' -RequiredProperty 'NTDS' -Attempts 6 -DelaySeconds 10 -ScriptBlock {
            $result = [pscustomobject]@{}
            $result.NTDS = (Get-Service NTDS -ErrorAction SilentlyContinue).Status
            $result.DNS = (Get-Service DNS -ErrorAction SilentlyContinue).Status
            $result.SSHD = (Get-Service sshd -ErrorAction SilentlyContinue).Status
            $result.Share = [bool](Get-SmbShare -Name 'LabShare' -ErrorAction SilentlyContinue)
            $result
        }

        if (-not $dcChecks) {
            throw 'DC1 check returned no structured data.'
        }

        if ($dcChecks.NTDS -eq 'Running') { Add-Ok 'DC1 NTDS running' } else { Add-Issue 'DC1 NTDS not running' }
        if ($dcChecks.DNS -eq 'Running') { Add-Ok 'DC1 DNS running' } else { Add-Issue 'DC1 DNS not running' }
        if ($dcChecks.SSHD -eq 'Running') { Add-Ok 'DC1 sshd running' } else { Add-Issue 'DC1 sshd not running' }
        if ($dcChecks.Share) { Add-Ok 'DC1 LabShare present' } else { Add-Issue 'DC1 LabShare missing' }
    } catch {
        Add-Issue "DC1 health checks failed: $($_.Exception.Message)"
    }

    try {
        $wsChecks = Invoke-LabStructuredCheck -ComputerName 'WS1' -RequiredProperty 'AppIDSvc' -Attempts 4 -DelaySeconds 10 -ScriptBlock {
            param($Domain)
            $result = [pscustomobject]@{}
            $result.AppIDSvc = (Get-Service AppIDSvc -ErrorAction SilentlyContinue).Status
            $result.LDrive = Test-Path 'L:\'
            $cs = Get-CimInstance Win32_ComputerSystem
            $result.PartOfDomain = [bool]$cs.PartOfDomain
            $result.Domain = $cs.Domain
            $dns = Resolve-DnsName -Name "dc1.$Domain" -ErrorAction SilentlyContinue
            $result.DnsOk = [bool]$dns
            $result
        } -ArgumentList $DomainName

        if (-not $wsChecks) {
            throw 'WS1 check returned no structured data.'
        }

        if ($wsChecks.AppIDSvc -eq 'Running') { Add-Ok 'WS1 AppIDSvc running' } else { Add-Issue 'WS1 AppIDSvc not running' }
        if ($wsChecks.LDrive) { Add-Ok 'WS1 L: mapped' } else { Add-Issue 'WS1 L: not mapped' }
        if ($wsChecks.PartOfDomain -and $wsChecks.Domain -ieq $DomainName) { Add-Ok 'WS1 domain join healthy' } else { Add-Issue "WS1 domain join invalid ($($wsChecks.Domain))" }
        if ($wsChecks.DnsOk) { Add-Ok 'WS1 DNS resolution works for DC1' } else { Add-Issue 'WS1 DNS resolution for DC1 failed' }
    } catch {
        Add-Issue "WS1 health checks failed: $($_.Exception.Message)"
    }

    if ($IncludeLIN1) {
        try {
            $linInstallerDvd = Get-VMDvdDrive -VMName 'LIN1' -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -and $_.Path -match '(?i)ubuntu-24\.04.*\.iso' }
            if ($linInstallerDvd) {
                Add-Issue 'LIN1 installer ISO is still attached (VM may boot back into installer).'
            } else {
                Add-Ok 'LIN1 installer ISO detached'
            }
        } catch {
            Add-Issue "LIN1 installer-media check failed: $($_.Exception.Message)"
        }

        try {
            $linDnsCmd = 'if getent hosts dc1.' + $DomainName + ' >/dev/null 2>&1; then echo yes; else echo no; fi'
            $linChecks = Invoke-LabCommand -ComputerName 'LIN1' -PassThru -ScriptBlock {
                param($DnsCmd)
                $result = @{}
                $mountState = bash -lc 'if mountpoint -q /mnt/labshare; then echo yes; else echo no; fi'
                $result.Mounted = (($mountState | Select-Object -First 1).ToString().Trim() -eq 'yes')
                $dnsState = bash -lc $DnsCmd
                $result.DnsOk = (($dnsState | Select-Object -First 1).ToString().Trim() -eq 'yes')
                $result
            } -ArgumentList $linDnsCmd

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
                    $sshOut = & $sshExe -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -i $SSHKeyPath "$LinuxUser@$LIN1_Ip" 'echo ok' 2>&1
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
    } else {
        Add-Ok 'LIN1 checks skipped (core mode)'
    }
}

if ($issues.Count -gt 0) {
    throw "Health gate failed with $($issues.Count) issue(s)."
}

Write-Host "`nHealth gate passed." -ForegroundColor Green
