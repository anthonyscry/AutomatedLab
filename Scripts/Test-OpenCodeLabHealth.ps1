# Test-OpenCodeLabHealth.ps1 - strict post-deploy health gate for OpenCodeLab

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
$CommonPath = Join-Path $RepoRoot 'Lab-Common.ps1'
if (Test-Path $CommonPath) { . $CommonPath }

# Lab-Config.ps1 already loaded via dot-source above - no legacy variable fallbacks needed

$ExpectedVMs = if ($IncludeLIN1) { @(@($GlobalLabConfig.Lab.CoreVMNames) + 'LIN1' | Select-Object -Unique) } else { @(@($GlobalLabConfig.Lab.CoreVMNames) | Where-Object { $_ -ne 'LIN1' }) }
$SSHKeyPath = Join-Path $GlobalLabConfig.Paths.LabSourcesRoot 'SSHKeys\id_ed25519'
$issues = New-Object System.Collections.Generic.List[string]
. (Join-Path $ScriptDir 'Helpers-TestReport.ps1')

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
    Write-Host "  Mode: WINDOWS CORE (LIN1 checks skipped)" -ForegroundColor Yellow
}

try {
    $null = Import-Module AutomatedLab -ErrorAction Stop
    Write-Verbose "Importing lab '$($GlobalLabConfig.Lab.Name)'..."
    $null = Import-Lab -Name $GlobalLabConfig.Lab.Name -ErrorAction Stop
    Add-Ok "Imported lab '$($GlobalLabConfig.Lab.Name)'"
} catch {
    Add-Issue "Unable to import lab '$($GlobalLabConfig.Lab.Name)': $($_.Exception.Message)"
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

# Infrastructure checks - vSwitch, NAT, gateway IP
$sw = Get-VMSwitch -Name $GlobalLabConfig.Network.SwitchName -ErrorAction SilentlyContinue
if ($sw) {
    Add-Ok "vSwitch '$($GlobalLabConfig.Network.SwitchName)' exists"
} else {
    Add-Issue "vSwitch '$($GlobalLabConfig.Network.SwitchName)' missing. Run: New-LabSwitch -SwitchName '$($GlobalLabConfig.Network.SwitchName)'"
}

$nat = Get-NetNat -Name $GlobalLabConfig.Network.NatName -ErrorAction SilentlyContinue
if ($nat) {
    Add-Ok "NAT '$($GlobalLabConfig.Network.NatName)' exists"
} else {
    Add-Issue "NAT '$($GlobalLabConfig.Network.NatName)' missing. Run: New-LabNAT"
}

$ifAlias = "vEthernet ($($GlobalLabConfig.Network.SwitchName))"
$gwIp = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $GlobalLabConfig.Network.GatewayIp }
if ($gwIp) {
    Add-Ok "Host gateway IP $($GlobalLabConfig.Network.GatewayIp) on $ifAlias"
} else {
    Add-Issue "Host gateway IP $($GlobalLabConfig.Network.GatewayIp) missing on $ifAlias"
}

if (-not $issues.Count) {
    try {
        $dcChecks = Invoke-LabStructuredCheck -ComputerName 'DC1' -RequiredProperty 'NTDS' -Attempts 6 -DelaySeconds 10 -ScriptBlock {
            [pscustomobject]@{
                NTDS = (Get-Service NTDS -ErrorAction SilentlyContinue).Status
                DNS = (Get-Service DNS -ErrorAction SilentlyContinue).Status
                SSHD = (Get-Service sshd -ErrorAction SilentlyContinue).Status
                Share = [bool](Get-SmbShare -Name 'LabShare' -ErrorAction SilentlyContinue)
            }
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

    # Test that DC1 can resolve external DNS (forwarders working)
    try {
        $dnsResult = Invoke-LabCommand -ComputerName 'DC1' -PassThru -ScriptBlock {
            $resolved = Resolve-DnsName -Name 'google.com' -QuickTimeout -ErrorAction SilentlyContinue
            [bool]$resolved
        } -ErrorAction SilentlyContinue
        if ($dnsResult) {
            Add-Ok 'DC1 DNS external resolution working'
        } else {
            Add-Issue 'DC1 cannot resolve external DNS. Check forwarders: Get-DnsServerForwarder on DC1'
        }
    } catch {
        Add-Issue "DC1 DNS resolution check failed: $($_.Exception.Message)"
    }

    # Check domain join status for member servers (SVR1)
    foreach ($memberVM in @($ExpectedVMs | Where-Object { $_ -notin @('DC1', 'LIN1') })) {
        try {
            $joinCheck = Invoke-LabStructuredCheck -ComputerName $memberVM -RequiredProperty 'Domain' -ScriptBlock {
                $cs = Get-CimInstance Win32_ComputerSystem
                [pscustomobject]@{ Domain = $cs.Domain; PartOfDomain = $cs.PartOfDomain }
            } -ErrorAction SilentlyContinue
            if ($joinCheck -and $joinCheck.PartOfDomain) {
                Add-Ok "$memberVM joined to domain '$($joinCheck.Domain)'"
            } else {
                Add-Issue "$memberVM not joined to domain. Expected: '$($GlobalLabConfig.Lab.DomainName)'"
            }
        } catch {
            Add-Issue "$memberVM domain join check failed: $($_.Exception.Message)"
        }
    }

    try {
        $wsChecks = Invoke-LabStructuredCheck -ComputerName 'WS1' -RequiredProperty 'AppIDSvc' -Attempts 4 -DelaySeconds 10 -ScriptBlock {
            param($Domain)
            $lDrive = Test-Path 'L:\'
            $shareReachable = Test-Path '\\DC1\LabShare'
            $cs = Get-CimInstance Win32_ComputerSystem
            $dns = Resolve-DnsName -Name "dc1.$Domain" -ErrorAction SilentlyContinue
            [pscustomobject]@{
                AppIDSvc = (Get-Service AppIDSvc -ErrorAction SilentlyContinue).Status
                LDrive = $lDrive
                ShareReachable = $shareReachable
                PartOfDomain = [bool]$cs.PartOfDomain
                Domain = $cs.Domain
                DnsOk = [bool]$dns
            }
        } -ArgumentList $GlobalLabConfig.Lab.DomainName

        if (-not $wsChecks) {
            throw 'WS1 check returned no structured data.'
        }

        if ($wsChecks.AppIDSvc -eq 'Running') { Add-Ok 'WS1 AppIDSvc running' } else { Add-Issue 'WS1 AppIDSvc not running' }
        if ($wsChecks.LDrive) {
            Add-Ok 'WS1 L: mapped'
        } elseif ($wsChecks.ShareReachable) {
            Add-Ok 'WS1 LabShare reachable via UNC (L: not mapped in service context)'
        } else {
            Add-Issue 'WS1 LabShare not reachable (L: and UNC both unavailable)'
        }
        if ($wsChecks.PartOfDomain -and $wsChecks.Domain -ieq $GlobalLabConfig.Lab.DomainName) { Add-Ok 'WS1 domain join healthy' } else { Add-Issue "WS1 domain join invalid ($($wsChecks.Domain))" }
        if ($wsChecks.DnsOk) { Add-Ok 'WS1 DNS resolution works for DC1' } else { Add-Issue 'WS1 DNS resolution for DC1 failed' }
    } catch {
        Add-Issue "WS1 health checks failed: $($_.Exception.Message)"
    }

    if ($ExpectedVMs -contains 'WSUS1') {
        try {
            $wsusChecks = Invoke-LabStructuredCheck -ComputerName 'WSUS1' -RequiredProperty 'PartOfDomain' -Attempts 4 -DelaySeconds 10 -ScriptBlock {
                param($Domain)
                $cs = Get-CimInstance Win32_ComputerSystem
                $dns = Resolve-DnsName -Name "dc1.$Domain" -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    PartOfDomain = [bool]$cs.PartOfDomain
                    Domain = $cs.Domain
                    DnsOk = [bool]$dns
                    WinRM = (Get-Service WinRM -ErrorAction SilentlyContinue).Status
                    LanmanServer = (Get-Service LanmanServer -ErrorAction SilentlyContinue).Status
                }
            } -ArgumentList $GlobalLabConfig.Lab.DomainName

            if (-not $wsusChecks) {
                throw 'WSUS1 check returned no structured data.'
            }

            if ($wsusChecks.PartOfDomain -and $wsusChecks.Domain -ieq $GlobalLabConfig.Lab.DomainName) { Add-Ok 'WSUS1 domain join healthy' } else { Add-Issue "WSUS1 domain join invalid ($($wsusChecks.Domain))" }
            if ($wsusChecks.DnsOk) { Add-Ok 'WSUS1 DNS resolution works for DC1' } else { Add-Issue 'WSUS1 DNS resolution for DC1 failed' }
            if ($wsusChecks.WinRM -eq 'Running') { Add-Ok 'WSUS1 WinRM running' } else { Add-Issue 'WSUS1 WinRM not running' }
            if ($wsusChecks.LanmanServer -eq 'Running') { Add-Ok 'WSUS1 Server service running' } else { Add-Issue 'WSUS1 Server service not running' }
        } catch {
            Add-Issue "WSUS1 health checks failed: $($_.Exception.Message)"
        }
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
            $linDnsCmd = 'if getent hosts dc1.' + $GlobalLabConfig.Lab.DomainName + ' >/dev/null 2>&1; then echo yes; else echo no; fi'
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

        # SSH-based health checks (work even without AutomatedLab registration)
        try {
            $sshInfo = Get-LinuxSSHConnectionInfo -VMName 'LIN1'
            if ($sshInfo) {
                $sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
                $sshBase = @('-o','StrictHostKeyChecking=accept-new','-o',"UserKnownHostsFile=$($GlobalLabConfig.SSH.KnownHostsPath)",'-o',"ConnectTimeout=$($GlobalLabConfig.Timeouts.Linux.SSHConnectTimeout)",'-i',$SSHKeyPath,"$($GlobalLabConfig.Credentials.LinuxUser)@$($sshInfo.IP)")

                # Check SSH service
                $sshdOut = & $sshExe @sshBase 'systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null' 2>&1
                if ($LASTEXITCODE -eq 0 -and ($sshdOut | Out-String).Trim() -eq 'active') {
                    Add-Ok 'LIN1 SSH service active'
                } else {
                    Add-Issue 'LIN1 SSH service not active'
                }

                # Check disk space (warn if root > 90%)
                $diskOut = & $sshExe @sshBase "df / --output=pcent | tail -1 | tr -d ' %'" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $usedPct = [int]($diskOut | Out-String).Trim()
                    if ($usedPct -ge 90) {
                        Add-Issue "LIN1 root disk usage at ${usedPct}% (>= 90%)"
                    } else {
                        Add-Ok "LIN1 root disk usage at ${usedPct}%"
                    }
                }

                # Check package manager
                $aptOut = & $sshExe @sshBase 'apt-get check 2>&1 && echo APT_OK' 2>&1
                if (($aptOut | Out-String) -match 'APT_OK') {
                    Add-Ok 'LIN1 apt package manager healthy'
                } else {
                    Add-Issue 'LIN1 apt package manager has issues'
                }
            }
        } catch {
            Write-Verbose "LIN1 SSH-based checks failed: $($_.Exception.Message)"
        }

        try {
            if (-not (Test-Path $SSHKeyPath)) {
                Add-Issue "Host SSH key missing: $SSHKeyPath"
            } else {
                $sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
                if (-not (Test-Path $sshExe)) {
                    Add-Issue 'Host OpenSSH client (ssh.exe) not found'
                } else {
                    $sshOut = & $sshExe -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -i $SSHKeyPath "$($GlobalLabConfig.Credentials.LinuxUser)@$($GlobalLabConfig.IPPlan.LIN1)" 'echo ok' 2>&1
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
