# Lab-Common.ps1 -- Shared helpers for OpenCode Dev Lab workflow scripts
#
# REGIONS:
#   - AutomatedLab Import: Module loading
#   - VM Lifecycle: Ensure-VMRunning, Remove-HyperVVMStale, Ensure-VMsReady
#   - Linux VM Networking & SSH: IP detection, DHCP, SSH connection
#   - SSH & Git Identity: Key management, identity helpers
#   - Linux VM Remote Execution: Invoke-BashOnLinuxVM, Join-LinuxToDomain
#   - Linux VM Provisioning: CIDATA, golden VHDX, VM creation
#   - Reporting: Deployment report generation
#   - Backward-Compatible Aliases
#
# FUTURE: Split into focused modules (VM-Lifecycle.ps1, Linux-SSH.ps1,
#         Linux-Provisioning.ps1, Reporting.ps1) when consumer scripts
#         are updated to use module imports instead of dot-sourcing.

Set-StrictMode -Version Latest

function Write-LabStatus {
    <#
    .SYNOPSIS
    Unified status output with consistent prefixes and colors.
    .PARAMETER Status
    One of: OK, WARN, FAIL, INFO, SKIP, CACHE, NOTE
    .PARAMETER Message
    The message text.
    .PARAMETER Indent
    Number of 2-space indentation levels (default: 1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OK','WARN','FAIL','INFO','SKIP','CACHE','NOTE')]
        [string]$Status,
        [Parameter(Mandatory)]
        [string]$Message,
        [int]$Indent = 1
    )

    $pad = '  ' * $Indent
    $colorMap = @{
        OK    = 'Green'
        WARN  = 'Yellow'
        FAIL  = 'Red'
        INFO  = 'Gray'
        SKIP  = 'DarkGray'
        CACHE = 'DarkGray'
        NOTE  = 'Cyan'
    }

    $color = $colorMap[$Status]
    Write-Host "${pad}[$Status] $Message" -ForegroundColor $color
}

#region AutomatedLab Import

function Import-OpenCodeLab {
    param([string]$Name)

    try {
        Import-Module AutomatedLab -ErrorAction Stop | Out-Null
    } catch {
        throw "AutomatedLab module not available. Install AutomatedLab first."
    }

    try {
        Import-Lab -Name $Name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

#endregion AutomatedLab Import

#region VM Lifecycle

function Ensure-VMRunning {
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $VMNames,
        [switch] $AutoStart
    )
    $missing = @()
    foreach ($n in $VMNames) {
        $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
        if (-not $vm) { $missing += $n; continue }
        if ($vm.State -ne 'Running') {
            if ($AutoStart) {
                try {
                    Start-VM -Name $n -ErrorAction Stop | Out-Null
                } catch {
                    # VM may have started between our check and this call
                    $refreshedVm = Get-VM -Name $n -ErrorAction SilentlyContinue
                    if (-not $refreshedVm -or $refreshedVm.State -ne 'Running') {
                        throw "Failed to start VM '$n': $($_.Exception.Message)"
                    }
                }
            } else {
                return $false
            }
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing Hyper-V VM(s): $($missing -join ', ')"
    }
    # If we autostarted, wait a moment for adapters to populate
    Start-Sleep -Seconds 2
    return $true
}

function Remove-HyperVVMStale {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VMName,
        [Parameter()][string]$Context = 'cleanup',
        [Parameter()][int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vm) { return $true }

        Write-Host "    [WARN] Found VM '$VMName' during $Context (attempt $attempt/$MaxAttempts). Removing..." -ForegroundColor Yellow

        Hyper-V\Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMSnapshot -ErrorAction SilentlyContinue | Out-Null

        Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMDvdDrive -ErrorAction SilentlyContinue | Out-Null

        if ($vm.State -like 'Saved*') {
            Hyper-V\Remove-VMSavedState -VMName $VMName -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 1
            $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        }

        if ($vm -and $vm.State -ne 'Off') {
            Hyper-V\Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 2
        }

        Hyper-V\Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $stillThere = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $stillThere) {
            Write-Host "    [OK] Removed VM '$VMName'" -ForegroundColor Green
            return $true
        }

        $vmId = $stillThere.VMId.Guid
        $vmwp = Get-CimInstance Win32_Process -Filter "Name='vmwp.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$vmId*" } |
            Select-Object -First 1
        if ($vmwp) {
            Stop-Process -Id $vmwp.ProcessId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }

    return -not (Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue)
}

function Ensure-VMsReady {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$VMNames,
        [switch]$NonInteractive,
        [switch]$AutoStart
    )
    if (-not (Ensure-VMRunning -VMNames $VMNames)) {
        if ($NonInteractive -or $AutoStart) {
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        } else {
            $vmList = $VMNames -join ', '
            $start = Read-Host "  $vmList not running. Start now? (y/n)"
            if ($start -ne 'y') { exit 0 }
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        }
    }
}

#endregion VM Lifecycle

#region Linux VM Networking & SSH

function Get-LinuxVMIPv4 {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1'
    )

    $adapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $adapter) { return $null }

    $ipList = @()
    if ($adapter.PSObject.Properties.Name -contains 'IPAddresses') {
        $ipList = @($adapter.IPAddresses)
    }

    $ip = $ipList |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } |
        Select-Object -First 1
    return $ip
}

function Get-LinuxVMDhcpLeaseIPv4 {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [string]$DhcpServer = 'DC1',
        [string]$ScopeId = '192.168.11.0'
    )

    $adapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $adapter -or [string]::IsNullOrWhiteSpace($adapter.MacAddress)) {
        return $null
    }

    $macCompact = ($adapter.MacAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($macCompact.Length -ne 12) { return $null }
    $macHyphen = ($macCompact -replace '(.{2})(?=.)','$1-').TrimEnd('-')

    try {
        $leaseResult = Invoke-LabCommand -ComputerName $DhcpServer -PassThru -ErrorAction SilentlyContinue -ScriptBlock {
            param($LeaseScope, $MacCompactArg, $MacHyphenArg, $VmNameArg)

            $leases = Get-DhcpServerv4Lease -ScopeId $LeaseScope -ErrorAction SilentlyContinue
            if (-not $leases) { return $null }

            $match = $leases | Where-Object {
                $cid = (($_.ClientId | Out-String).Trim() -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
                $cid -eq $MacCompactArg
            } | Select-Object -First 1

            if (-not $match) {
                $match = $leases | Where-Object {
                    (($_.ClientId | Out-String).Trim().ToUpperInvariant() -eq $MacHyphenArg) -or
                    ($_.HostName -eq $VmNameArg)
                } | Select-Object -First 1
            }

            if ($match -and $match.IPAddress) {
                return $match.IPAddress.IPAddressToString
            }

            return $null
        } -ArgumentList $ScopeId, $macCompact, $macHyphen, $VMName

        if ($leaseResult) {
            return ($leaseResult | Select-Object -First 1)
        }
    } catch {
        return $null
    }

    return $null
}

function Wait-LinuxVMReady {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [int]$WaitMinutes = 30,
        [string]$DhcpServer = 'DC1',
        [string]$ScopeId = '192.168.11.0',
        [int]$PollInitialSec = 15,
        [int]$PollMaxSec = 45
    )

    $deadline = [datetime]::Now.AddMinutes($WaitMinutes)
    $lastKnownIp = ''
    $lastLeaseIp = ''
    $waitTick = 0

    $pollInterval = [math]::Max(1, $PollInitialSec)
    $pollCap = [math]::Max(1, $PollMaxSec)
    if ($pollInterval -gt $pollCap) {
        $pollInterval = $pollCap
    }

    while ([datetime]::Now -lt $deadline) {
        $waitTick++

        $vmIp = Get-LinuxVMIPv4 -VMName $VMName
        if ($vmIp) {
            $lastKnownIp = $vmIp
            $sshCheck = Test-NetConnection -ComputerName $vmIp -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($sshCheck.TcpTestSucceeded) {
                Write-Host "  [OK] $VMName SSH is reachable at $vmIp" -ForegroundColor Green
                return @{ Ready = $true; IP = $vmIp; LeaseIP = $lastLeaseIp }
            }
        }

        if (-not $lastKnownIp) {
            $leaseIp = Get-LinuxVMDhcpLeaseIPv4 -VMName $VMName -DhcpServer $DhcpServer -ScopeId $ScopeId
            if ($leaseIp) {
                $lastLeaseIp = $leaseIp
            }
        }

        if ($lastKnownIp) {
            Write-Host "    $VMName has IP ($lastKnownIp), waiting for SSH..." -ForegroundColor Gray
        }
        elseif ($lastLeaseIp) {
            Write-Host "    DHCP lease seen for $VMName ($lastLeaseIp), waiting for Hyper-V guest IP + SSH..." -ForegroundColor Gray
        }
        else {
            Write-Host "    Still waiting for $VMName DHCP lease..." -ForegroundColor Gray
        }

        if (($waitTick % 6) -eq 0) {
            $vmState = (Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
            Write-Host "    $VMName VM state: $vmState" -ForegroundColor DarkGray
        }

        Start-Sleep -Seconds $pollInterval
        $pollInterval = [math]::Min([int][math]::Ceiling($pollInterval * 1.5), $pollCap)
    }

    Write-Host "  [WARN] $VMName did not become SSH-reachable after $WaitMinutes min." -ForegroundColor Yellow
    if ($lastLeaseIp) {
        Write-Host "  [INFO] $VMName DHCP lease observed at: $lastLeaseIp" -ForegroundColor DarkGray
    }

    return @{ Ready = $false; IP = $lastKnownIp; LeaseIP = $lastLeaseIp }
}

function Get-LinuxSSHConnectionInfo {
    <#
    .SYNOPSIS
    Returns SSH connection details for a Linux VM.
    .DESCRIPTION
    Resolves the VM's IP address and constructs an SSH command string.
    Returns $null if the VM is not reachable.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [string]$User = $(if ($LinuxUser) { $LinuxUser } else { 'labadmin' }),
        [string]$KeyPath = $(if ($SSHPrivateKey) { $SSHPrivateKey } else { 'C:\LabSources\SSHKeys\id_ed25519' })
    )

    $ip = Get-LinuxVMIPv4 -VMName $VMName
    if (-not $ip) { return $null }

    $sshCmd = "ssh -o StrictHostKeyChecking=no -i `"$KeyPath`" $User@$ip"

    return @{
        VMName  = $VMName
        IP      = $ip
        User    = $User
        KeyPath = $KeyPath
        Command = $sshCmd
    }
}

function Add-LinuxDhcpReservation {
    <#
    .SYNOPSIS
    Creates a DHCP reservation on DC1 for a Linux VM's MAC address.
    .DESCRIPTION
    Reads the VM's MAC from Hyper-V and creates a DHCP reservation via
    Invoke-LabCommand on the DHCP server (DC1). This ensures the Linux VM
    always gets the same IP after reboot.
    NOTE: Requires AutomatedLab to be imported (Invoke-LabCommand prerequisite).
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [string]$ReservedIP = $(if ($LIN1_Ip) { $LIN1_Ip } else { '10.0.10.110' }),
        [string]$DhcpServer = 'DC1',
        [string]$ScopeId = $(if ($DhcpScopeId) { $DhcpScopeId } else { '10.0.10.0' })
    )

    $adapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $adapter -or [string]::IsNullOrWhiteSpace($adapter.MacAddress)) {
        Write-Warning "Cannot read MAC address for VM '$VMName'. Is it created?"
        return $false
    }

    $macRaw = ($adapter.MacAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($macRaw.Length -ne 12) {
        Write-Warning "Invalid MAC address for '$VMName': $($adapter.MacAddress)"
        return $false
    }

    # Format as AA-BB-CC-DD-EE-FF for DHCP server
    $macFormatted = ($macRaw -replace '(.{2})(?=.)', '$1-')

    try {
        Invoke-LabCommand -ComputerName $DhcpServer -ScriptBlock {
            param($ScopeArg, $IpArg, $MacArg, $NameArg)

            # Remove existing reservation for this MAC or IP if present
            Get-DhcpServerv4Reservation -ScopeId $ScopeArg -ErrorAction SilentlyContinue |
                Where-Object { $_.ClientId -eq $MacArg -or $_.IPAddress.IPAddressToString -eq $IpArg } |
                Remove-DhcpServerv4Reservation -ErrorAction SilentlyContinue

            Add-DhcpServerv4Reservation -ScopeId $ScopeArg `
                -IPAddress $IpArg `
                -ClientId $MacArg `
                -Name $NameArg `
                -Description "Linux VM $NameArg - auto-reserved" `
                -ErrorAction Stop

        } -ArgumentList $ScopeId, $ReservedIP, $macFormatted, $VMName

        Write-Host "    [OK] DHCP reservation: $VMName -> $ReservedIP (MAC: $macFormatted)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "DHCP reservation failed for '$VMName': $($_.Exception.Message)"
        return $false
    }
}

#endregion Linux VM Networking & SSH

#region SSH & Git Identity

function Ensure-SSHKey {
    param([string]$KeyPath)
    if (-not (Test-Path $KeyPath)) {
        throw "SSH key not found: $KeyPath`nGenerate it with: C:\Windows\System32\OpenSSH\ssh-keygen.exe -t ed25519 -f `"$KeyPath`" -N `"`""
    }
}

function Invoke-LinuxSSH {
    <#
    .SYNOPSIS
    Execute a command on a Linux VM via SSH.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$IP,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Command,
        [string]$User = $LinuxUser,
        [string]$KeyPath = $SSHPrivateKey,
        [int]$ConnectTimeout = $SSH_ConnectTimeout,
        [switch]$PassThru
    )

    $sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    if (-not (Test-Path $sshExe)) {
        throw "OpenSSH client not found at $sshExe. Install Windows optional feature: OpenSSH Client."
    }

    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=NUL',
        '-o', "ConnectTimeout=$ConnectTimeout",
        '-i', $KeyPath,
        "$User@$IP",
        $Command
    )

    if ($PassThru) {
        return (& $sshExe @sshArgs 2>&1)
    }
    else {
        & $sshExe @sshArgs 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
    }
}

function Copy-LinuxFile {
    <#
    .SYNOPSIS
    Copy a file to a Linux VM via SCP.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$IP,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$LocalPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RemotePath,
        [string]$User = $LinuxUser,
        [string]$KeyPath = $SSHPrivateKey
    )

    $scpExe = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
    if (-not (Test-Path $scpExe)) {
        throw "OpenSSH scp not found at $scpExe."
    }

    & $scpExe -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -i $KeyPath $LocalPath "${User}@${IP}:${RemotePath}" 2>&1 | Out-Null
}

function Get-GitIdentity {
    param([string]$DefaultName, [string]$DefaultEmail)

    $name  = $DefaultName
    $email = $DefaultEmail

    if ([string]::IsNullOrWhiteSpace($name))  { $name  = Read-Host "  Git user.name (e.g. Anthony Tran)" }
    if ([string]::IsNullOrWhiteSpace($email)) { $email = Read-Host "  Git user.email (e.g. you@domain)" }

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($email)) {
        throw "Git identity is required."
    }

    return @{ Name = $name; Email = $email }
}

#endregion SSH & Git Identity

#region Linux VM Remote Execution

function Invoke-BashOnLinuxVM {
    param(
        # Uses AutomatedLab Copy-LabFileItem / Invoke-LabCommand and requires the VM to be registered in AutomatedLab.
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VMName = 'LIN1',
        [Parameter(Mandatory)][string]$BashScript,
        [Parameter(Mandatory)][string]$ActivityName,
        [hashtable]$Variables = @{},
        [switch]$PassThru
    )
    # Apply variable substitutions (placeholder pattern: __KEY__)
    $content = $BashScript
    foreach ($key in $Variables.Keys) {
        $content = $content.Replace("__${key}__", $Variables[$key])
    }

    $tempName = "$ActivityName-$(Get-Date -Format 'HHmmss').sh"
    $tempPath = Join-Path $env:TEMP $tempName
    $content | Set-Content -Path $tempPath -Encoding ASCII -Force

    try {
        Copy-LabFileItem -Path $tempPath -ComputerName $VMName -DestinationFolderPath '/tmp'

        $invokeParams = @{
            ComputerName = $VMName
            ActivityName = $ActivityName
            ScriptBlock = {
                param($ScriptFile)
                chmod +x "/tmp/$ScriptFile"
                bash "/tmp/$ScriptFile"
            }
            ArgumentList = @($tempName)
        }
        if ($PassThru) { $invokeParams.PassThru = $true }

        Invoke-LabCommand @invokeParams
    } finally {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Join-LinuxToDomain {
    <#
    .SYNOPSIS
    Joins a Linux VM to the Active Directory domain via SSSD.
    .DESCRIPTION
    Connects via SSH and installs/configures realmd + SSSD for AD integration.
    Requires the domain controller to be reachable from the Linux VM.
    NOTE: Uses direct SSH — does not require AutomatedLab lab import.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [string]$DomainName = $(if ($DomainName) { $DomainName } else { 'simplelab.local' }),
        [string]$DomainAdmin = $(if ($LabInstallUser) { $LabInstallUser } else { 'Administrator' }),
        [string]$DomainPassword = $(if ($AdminPassword) { $AdminPassword } else { 'SimpleLab123!' }),
        [string]$User = $(if ($LinuxUser) { $LinuxUser } else { 'labadmin' }),
        [string]$KeyPath = $(if ($SSHPrivateKey) { $SSHPrivateKey } else { 'C:\LabSources\SSHKeys\id_ed25519' }),
        [int]$SSHTimeout = $(if ($SSH_ConnectTimeout) { $SSH_ConnectTimeout } else { 8 })
    )

    $ip = Get-LinuxVMIPv4 -VMName $VMName
    if (-not $ip) {
        Write-Warning "Cannot determine IP for '$VMName'. Is it running?"
        return $false
    }

    # The domain join script
    $joinScript = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[SSSD] Installing required packages..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq realmd sssd sssd-tools adcli packagekit samba-common-bin krb5-user

echo "[SSSD] Discovering domain $DomainName..."
`$SUDO realm discover $DomainName

echo "[SSSD] Joining domain $DomainName..."
echo '$DomainPassword' | `$SUDO realm join -U $DomainAdmin $DomainName --install=/

echo "[SSSD] Configuring SSSD..."
`$SUDO bash -c 'cat > /etc/sssd/sssd.conf << SSSDEOF
[sssd]
domains = $DomainName
config_file_version = 2
services = nss, pam

[$('domain/' + $DomainName)]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = $($DomainName.ToUpperInvariant())
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = $DomainName
use_fully_qualified_names = True
ldap_id_mapping = True
access_provider = ad
SSSDEOF'

`$SUDO chmod 600 /etc/sssd/sssd.conf
`$SUDO systemctl restart sssd

echo "[SSSD] Enabling home directory auto-creation..."
`$SUDO pam-auth-update --enable mkhomedir 2>/dev/null || true

echo "[SSSD] Domain join complete."
"@

    $tempScript = Join-Path $env:TEMP "domainjoin-$VMName.sh"
    $joinScript | Set-Content -Path $tempScript -Encoding ASCII -Force

    try {
        Copy-LinuxFile -IP $ip -LocalPath $tempScript -RemotePath '/tmp/domainjoin.sh' -User $User -KeyPath $KeyPath

        Write-Host "    Joining $VMName to domain $DomainName via SSSD..." -ForegroundColor Cyan
        Invoke-LinuxSSH -IP $ip -Command 'chmod +x /tmp/domainjoin.sh && bash /tmp/domainjoin.sh && rm -f /tmp/domainjoin.sh' -User $User -KeyPath $KeyPath -ConnectTimeout $SSHTimeout

        Write-Host "    [OK] $VMName joined to $DomainName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Domain join failed for '$VMName': $($_.Exception.Message)"
        return $false
    }
    finally {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

#endregion Linux VM Remote Execution

#region Linux VM Provisioning

function Get-Sha512PasswordHash {
    <#
    .SYNOPSIS
    Generate SHA512 crypt hash for Ubuntu autoinstall identity section.
    
    .PARAMETER Password
    The plain-text password to hash.
    
    .OUTPUTS
    String in $6$salt$hash format suitable for Ubuntu user-data password field.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Password
    )

    # Try OpenSSL first (if available)
    $opensslPaths = @(
        'C:\Program Files\OpenSSL-Win64\bin\openssl.exe',
        'C:\Program Files\OpenSSL\bin\openssl.exe',
        'C:\OpenSSL-Win64\bin\openssl.exe'
    )
    
    foreach ($opensslPath in $opensslPaths) {
        if (Test-Path $opensslPath) {
            try {
                $hash = & $opensslPath passwd -6 $Password 2>$null
                if ($LASTEXITCODE -eq 0 -and $hash -match '^\$6\$') {
                    return $hash.Trim()
                }
            } catch {
                Write-Verbose "OpenSSL hash attempt failed at '$opensslPath': $($_.Exception.Message)"
            }
        }
    }
    
    # Fallback: Use .NET crypto for SHA512 crypt hash generation
    Add-Type -AssemblyName System.Security
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $saltBytes = New-Object byte[] 16
    $rng.GetBytes($saltBytes)
    
    # Convert to base64-like charset for crypt salt [a-zA-Z0-9./]
    $saltChars = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    $salt = -join ($saltBytes | ForEach-Object { $saltChars[$_ % 64] })
    $salt = $salt.Substring(0, 16)
    
    # SHA512 crypt implementation (simplified - uses .NET SHA512)
    $sha512 = [System.Security.Cryptography.SHA512]::Create()
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $saltBytesActual = [System.Text.Encoding]::UTF8.GetBytes($salt)
    
    # Combine password and salt
    $combined = $passwordBytes + $saltBytesActual + $passwordBytes
    $hash = $sha512.ComputeHash($combined)
    
    # Base64-encode for crypt format
    $hashB64 = -join ($hash | ForEach-Object { $saltChars[$_ % 64] })
    
    return "`$6`$$salt`$$hashB64"
}

function New-CidataVhdx {
    <#
    .SYNOPSIS
    Create a CIDATA VHDX seed disk for Linux cloud-init.

    Uses a small FAT32-formatted VHDX with volume label "CIDATA" containing
    user-data and meta-data files. Cloud-init NoCloud datasource detects any
    filesystem labeled "CIDATA"/"cidata" -- no ISO tools (oscdimg) required.

    .PARAMETER OutputPath
    Path where the VHDX file will be created.

    .PARAMETER Hostname
    Hostname for the Ubuntu system.

    .PARAMETER Username
    Username for the initial user account.

    .PARAMETER PasswordHash
    SHA512 password hash (from Get-Sha512PasswordHash).

    .PARAMETER SSHPublicKey
    Optional SSH public key content to add to authorized_keys.

    .OUTPUTS
    Path to the created VHDX file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Hostname,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Username,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PasswordHash,
        [string]$SSHPublicKey = '',
        [ValidateSet('Ubuntu2404','Ubuntu2204','Rocky9')]
        [string]$Distro = 'Ubuntu2404'
    )

    # Cache: If CIDATA already exists, skip recreation (caller can delete to force rebuild)
    if (Test-Path $OutputPath) {
        Write-Host "    [CACHE] CIDATA VHDX exists, skipping: $OutputPath" -ForegroundColor DarkGray
        return $OutputPath
    }

    # Build distro-specific cloud-init user-data
    $ubuntuSshBlock = ''
    if ($SSHPublicKey) {
        $ubuntuSshBlock = @"

    authorized-keys:
      - $SSHPublicKey
"@
    }

    $rockySshBlock = @"
    ssh_authorized_keys: []
"@
    if ($SSHPublicKey) {
        $rockySshBlock = @"
    ssh_authorized_keys:
      - $SSHPublicKey
"@
    }

    switch ($Distro) {
        'Ubuntu2404' {
            $userData = @"
#cloud-config
autoinstall:
  version: 1
  interactive-sections: []
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    version: 2
    ethernets:
      primary:
        match:
          name: "e*"
        dhcp4: true
  identity:
    hostname: $Hostname
    username: $Username
    password: '$PasswordHash'
  storage:
    layout:
      name: lvm
  ssh:
    install-server: true
    allow-pw: true$ubuntuSshBlock
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  packages:
    - openssh-server
    - curl
    - wget
    - git
    - net-tools
"@
        }
        'Ubuntu2204' {
            $userData = @"
#cloud-config
# Ubuntu 22.04 compatible autoinstall format
autoinstall:
  version: 1
  interactive-sections: []
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    version: 2
    ethernets:
      primary:
        match:
          name: "e*"
        dhcp4: true
  identity:
    hostname: $Hostname
    username: $Username
    password: '$PasswordHash'
  storage:
    layout:
      name: lvm
  ssh:
    install-server: true
    allow-pw: true$ubuntuSshBlock
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  packages:
    - openssh-server
    - curl
    - wget
    - git
    - net-tools
"@
        }
        'Rocky9' {
            $userData = @"
#cloud-config
hostname: $Hostname
users:
  - name: $Username
    lock_passwd: false
    passwd: '$PasswordHash'
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
$rockySshBlock
packages:
  - openssh-server
  - curl
  - wget
  - git
  - net-tools
runcmd:
  - systemctl enable --now sshd
"@
        }
    }

    $metaData = @"
instance-id: iid-$Hostname-$(Get-Date -Format 'yyyyMMddHHmmss')
local-hostname: $Hostname
"@

    # Staging folder for the two files
    $staging = Join-Path $env:TEMP ("cidata-" + [guid]::NewGuid().ToString().Substring(0,8))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    try {
        [IO.File]::WriteAllText((Join-Path $staging 'user-data'), $userData, $utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $staging 'meta-data'), $metaData, $utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $staging 'autoinstall'), "", $utf8NoBom)

        # Create parent directory for the VHDX
        $dir = Split-Path $OutputPath -Parent
        if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

        # Create a small dynamic VHDX, partition, format FAT32 with label CIDATA
        New-VHD -Path $OutputPath -SizeBytes 64MB -Dynamic | Out-Null
        $mounted = Mount-VHD -Path $OutputPath -PassThru
        $diskNum = $mounted.DiskNumber

        Initialize-Disk -Number $diskNum -PartitionStyle GPT -PassThru | Out-Null
        $part = New-Partition -DiskNumber $diskNum -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Force | Out-Null

        $driveLetter = ($part | Get-Volume).DriveLetter
        $driveRoot = "${driveLetter}:\"
        Copy-Item (Join-Path $staging 'user-data') (Join-Path $driveRoot 'user-data') -Force
        Copy-Item (Join-Path $staging 'meta-data') (Join-Path $driveRoot 'meta-data') -Force
        Copy-Item (Join-Path $staging 'autoinstall') (Join-Path $driveRoot 'autoinstall') -Force

        Dismount-VHD -Path $OutputPath
        Write-Host "    [OK] CIDATA VHDX created: $OutputPath" -ForegroundColor Green
        return $OutputPath
    }
    catch {
        # Ensure VHD is dismounted on failure
        try {
            Dismount-VHD -Path $OutputPath -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "Cleanup dismount failed for '$OutputPath': $($_.Exception.Message)"
        }
        throw
    }
    finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-LinuxGoldenVhdx {
    <#
    .SYNOPSIS
    Creates a pre-installed golden VHDX template for Linux VMs.
    .DESCRIPTION
    If a golden template VHDX exists, New-LinuxVM can clone it instead of
    installing from ISO each time. This function creates the template by:
    1. Creating a temporary VM with the ISO + CIDATA
    2. Waiting for installation to complete
    3. Shutting down and saving the OS VHDX as the golden template

    Subsequent VMs can use Copy-Item on the golden VHDX instead of
    reinstalling from ISO (saves 15-25 minutes per VM).
    .PARAMETER TemplatePath
    Path where the golden VHDX template will be saved.
    .PARAMETER UbuntuIsoPath
    Path to the Ubuntu installation ISO.
    .PARAMETER Hostname
    Temporary hostname for the template VM.
    .PARAMETER Username
    Username for the template VM.
    .PARAMETER Password
    Password for the template VM.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TemplatePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UbuntuIsoPath,
        [string]$Hostname = 'golden-template',
        [string]$Username = 'labadmin',
        [string]$Password = 'Server123!',
        [string]$SwitchName = $LabSwitch,
        [int]$WaitMinutes = 45,
        [long]$DiskSize = 60GB
    )

    if (Test-Path $TemplatePath) {
        Write-Host "    [OK] Golden VHDX template already exists: $TemplatePath" -ForegroundColor Green
        return $TemplatePath
    }

    $templateDir = Split-Path $TemplatePath -Parent
    if ($templateDir) { New-Item -ItemType Directory -Path $templateDir -Force | Out-Null }

    $tempVMName = "GoldenTemplate-$(Get-Date -Format 'yyyyMMddHHmmss')"

    Write-Host "    Creating golden template VM '$tempVMName'..." -ForegroundColor Cyan

    $cidataPath = $null
    $tempVhdxPath = Join-Path $env:TEMP "$tempVMName.vhdx"

    try {
        # Generate password hash
        $pwHash = Get-Sha512PasswordHash -Password $Password

        # Create CIDATA for template
        $cidataPath = Join-Path $env:TEMP "$tempVMName-cidata.vhdx"
        New-CidataVhdx -OutputPath $cidataPath -Hostname $Hostname -Username $Username -PasswordHash $pwHash

        # Create temp VM
        New-LinuxVM -UbuntuIsoPath $UbuntuIsoPath -CidataVhdxPath $cidataPath `
            -VMName $tempVMName -VhdxPath $tempVhdxPath `
            -SwitchName $SwitchName -DiskSize $DiskSize

        Start-VM -Name $tempVMName
        Write-Host "    Template VM started. Waiting for install ($WaitMinutes min max)..." -ForegroundColor Gray

        # Wait for SSH or timeout
        $waitResult = Wait-LinuxVMReady -VMName $tempVMName -WaitMinutes $WaitMinutes

        if ($waitResult.Ready) {
            Write-Host "    Template installation complete. Shutting down..." -ForegroundColor Green
            Stop-VM -Name $tempVMName -Force
            Start-Sleep -Seconds 5

            # Finalize media
            Finalize-LinuxInstallMedia -VMName $tempVMName

            # Copy the OS VHDX as the golden template
            Copy-Item $tempVhdxPath $TemplatePath -Force
            Write-Host "    [OK] Golden VHDX template saved: $TemplatePath" -ForegroundColor Green
        } else {
            Write-Warning "Template VM did not become ready within $WaitMinutes minutes."
            Write-Warning "Golden template not created."
        }
    }
    finally {
        # Cleanup temp VM
        Remove-HyperVVMStale -VMName $tempVMName -Context 'golden-template-cleanup' | Out-Null
        if ($cidataPath) {
            Remove-Item $cidataPath -Force -ErrorAction SilentlyContinue
        }
        Remove-Item (Join-Path $env:TEMP "$tempVMName.vhdx") -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $TemplatePath) {
        return $TemplatePath
    }
    return $null
}

function New-LinuxVM {
    <#
    .SYNOPSIS
    Create Hyper-V Gen2 VM for a Linux Ubuntu 24.04 guest.

    Creates the VM, attaches the Ubuntu ISO as DVD for boot, and attaches
    the CIDATA VHDX as a second SCSI disk for cloud-init NoCloud discovery.

    .PARAMETER UbuntuIsoPath
    Path to Ubuntu 24.04 installation ISO.

    .PARAMETER CidataVhdxPath
    Path to CIDATA VHDX seed disk (from New-CidataVhdx).

    .PARAMETER VMName
    Name for the virtual machine (default: LIN1).

    .PARAMETER VhdxPath
    Path for the OS VHDX file (default: auto-generated under $LabPath).

    .PARAMETER SwitchName
    Hyper-V switch name (default: from Lab-Config.ps1 $LabSwitch).

    .PARAMETER Memory
    Startup memory (default: from Lab-Config.ps1 $UBU_Memory).

    .PARAMETER MinMemory
    Minimum memory (default: from Lab-Config.ps1 $UBU_MinMemory).

    .PARAMETER MaxMemory
    Maximum memory (default: from Lab-Config.ps1 $UBU_MaxMemory).

    .PARAMETER Processors
    Processor count (default: from Lab-Config.ps1 $UBU_Processors).

    .PARAMETER DiskSize
    OS disk size (default: 60GB).

    .OUTPUTS
    Microsoft.HyperV.PowerShell.VirtualMachine object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UbuntuIsoPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CidataVhdxPath,
        [string]$VMName = 'LIN1',
        [string]$VhdxPath = '',
        [string]$SwitchName = $(if ($LabSwitch) { $LabSwitch } else { 'AutomatedLab' }),
        [long]$Memory = $(if ($UBU_Memory) { $UBU_Memory } else { 2GB }),
        [long]$MinMemory = $(if ($UBU_MinMemory) { $UBU_MinMemory } else { 1GB }),
        [long]$MaxMemory = $(if ($UBU_MaxMemory) { $UBU_MaxMemory } else { 4GB }),
        [int]$Processors = $(if ($UBU_Processors) { $UBU_Processors } else { 2 }),
        [long]$DiskSize = 60GB
    )

    if (-not (Test-Path $UbuntuIsoPath)) { throw "Ubuntu ISO not found: $UbuntuIsoPath" }
    if (-not (Test-Path $CidataVhdxPath)) { throw "CIDATA VHDX not found: $CidataVhdxPath" }

    if (-not $VhdxPath) {
        $VhdxPath = Join-Path $LabPath "$VMName\$VMName.vhdx"
    }
    $vhdxDir = Split-Path $VhdxPath -Parent
    if ($vhdxDir) { New-Item -ItemType Directory -Path $vhdxDir -Force | Out-Null }

    # Create Gen2 VM with dynamic memory
    $vm = Hyper-V\New-VM -Name $VMName -Generation 2 `
        -MemoryStartupBytes $Memory `
        -NewVHDPath $VhdxPath -NewVHDSizeBytes $DiskSize `
        -SwitchName $SwitchName -ErrorAction Stop

    Hyper-V\Set-VM -VM $vm -DynamicMemory `
        -MemoryMinimumBytes $MinMemory -MemoryMaximumBytes $MaxMemory `
        -ProcessorCount $Processors `
        -AutomaticCheckpointsEnabled $false -ErrorAction Stop

    # Disable Secure Boot (required for Ubuntu on Gen2)
    Hyper-V\Set-VMFirmware -VM $vm -EnableSecureBoot Off -ErrorAction Stop

    # Attach Ubuntu ISO as DVD for installation boot
    Hyper-V\Add-VMDvdDrive -VM $vm -Path $UbuntuIsoPath -ErrorAction Stop

    # Attach CIDATA VHDX as second SCSI disk (cloud-init NoCloud seed)
    Hyper-V\Add-VMHardDiskDrive -VM $vm -Path $CidataVhdxPath -ErrorAction Stop

    # Set boot order: DVD first (Ubuntu ISO), then hard disk (OS)
    $dvd = Hyper-V\Get-VMDvdDrive -VM $vm | Select-Object -First 1
    $hdd = Hyper-V\Get-VMHardDiskDrive -VM $vm | Where-Object { $_.Path -eq $VhdxPath } | Select-Object -First 1
    Hyper-V\Set-VMFirmware -VM $vm -BootOrder $dvd, $hdd -ErrorAction Stop

    Write-Host "    [OK] VM '$VMName' created (Gen2, SecureBoot=Off, DVD+CIDATA)" -ForegroundColor Green
    return Hyper-V\Get-VM -Name $VMName
}

function Finalize-LinuxInstallMedia {
    <#
    .SYNOPSIS
    Finalize Linux VM boot media after Ubuntu install completes.

    Removes installer DVD/CIDATA devices and sets firmware to boot from OS disk
    so the VM does not return to the Ubuntu installer wizard on subsequent boots.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1'
    )

    $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Verbose "VM '$VMName' not found; skipping install-media finalization."
        return $false
    }

    $osDisk = Hyper-V\Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -notmatch '(?i)cidata' } |
        Select-Object -First 1
    if ($osDisk) {
        try {
            Hyper-V\Set-VMFirmware -VMName $VMName -FirstBootDevice $osDisk -ErrorAction Stop
            Write-Host "    [OK] $VMName firmware set to boot from OS disk" -ForegroundColor Green
        } catch {
            Write-Verbose "Unable to set first boot device for '$VMName': $($_.Exception.Message)"
        }
    }

    Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue |
        ForEach-Object {
            $dvd = $_
            try {
                Hyper-V\Remove-VMDvdDrive -VMDvdDrive $dvd -ErrorAction Stop
                Write-Host "    [OK] Detached installer DVD from $VMName" -ForegroundColor Green
            } catch {
                Write-Verbose "Unable to remove DVD drive from '$VMName': $($_.Exception.Message)"
            }
        }

    Hyper-V\Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -match '(?i)cidata' } |
        ForEach-Object {
            $seed = $_
            try {
                Hyper-V\Remove-VMHardDiskDrive -VMHardDiskDrive $seed -ErrorAction Stop
                Write-Host "    [OK] Detached CIDATA seed disk from $VMName" -ForegroundColor Green
            } catch {
                Write-Verbose "Unable to detach CIDATA disk from '$VMName': $($_.Exception.Message)"
            }

            if ($seed.Path -and (Test-Path $seed.Path)) {
                Remove-Item $seed.Path -Force -ErrorAction SilentlyContinue
            }
        }

    return $true
}

#endregion Linux VM Provisioning

#region Reporting

function New-LabDeploymentReport {
    <#
    .SYNOPSIS
    Generates a deployment recap report in HTML and console format.
    .DESCRIPTION
    Creates a summary of all deployed VMs, their roles, IPs, and status.
    Outputs both an HTML file and console-formatted text.
    .PARAMETER Machines
    Array of hashtables with machine info (VMName, IP, OS tag, Roles, Status).
    .PARAMETER LabName
    Name of the lab deployment.
    .PARAMETER OutputPath
    Directory to save the HTML report.
    .PARAMETER StartTime
    When the deployment started.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Machines,
        [string]$LabName = 'AutomatedLab',
        [string]$OutputPath = $LabPath,
        [datetime]$StartTime = [datetime]::Now
    )

    $endTime = [datetime]::Now
    $duration = $endTime - $StartTime
    $durationStr = '{0:D2}h {1:D2}m {2:D2}s' -f [int]$duration.TotalHours, $duration.Minutes, $duration.Seconds
    $timestamp = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
    $dateStamp = $endTime.ToString('yyyyMMdd-HHmmss')

    Write-Host ""
    Write-Host '  +----------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |           DEPLOYMENT RECAP REPORT            |' -ForegroundColor Cyan
    Write-Host '  +----------------------------------------------+' -ForegroundColor Cyan
    Write-Host ('  Lab:       {0}' -f $LabName) -ForegroundColor White
    Write-Host ('  Completed: {0}' -f $timestamp) -ForegroundColor White
    Write-Host ('  Duration:  {0}' -f $durationStr) -ForegroundColor White
    Write-Host ('  Machines:  {0}' -f $Machines.Count) -ForegroundColor White
    Write-Host ''

    Write-Host '  VM Name      OS      IP                Role(s)               Status' -ForegroundColor Gray
    Write-Host '  -------      --      --                -------               ------' -ForegroundColor Gray
    foreach ($m in $Machines) {
        $rolesText = @($m.Roles) -join ', '
        if ($rolesText.Length -gt 20) { $rolesText = $rolesText.Substring(0, 17) + '...' }
        $status = [string]$m.Status
        $statusColor = if ($status -eq 'OK') { 'Green' } elseif ($status -eq 'WARN') { 'Yellow' } else { 'Red' }

        Write-Host ('  {0,-12} {1,-7} {2,-17} {3,-20} ' -f $m.VMName, $m.OSTag, $m.IP, $rolesText) -NoNewline -ForegroundColor Gray
        Write-Host $status -ForegroundColor $statusColor
    }

    Write-Host ''
    Write-Host '  CONNECTION INFO:' -ForegroundColor Yellow
    foreach ($m in $Machines) {
        if ($m.OSTag -eq '[LIN]') {
            Write-Host ('    {0}: ssh -i $SSHPrivateKey {1}@{2}' -f $m.VMName, $LinuxUser, $m.IP) -ForegroundColor Gray
        }
        else {
            $rdpUser = '{0}\{1}' -f $DomainName, $LabInstallUser
            Write-Host ('    {0}: RDP to {1} ({2})' -f $m.VMName, $m.IP, $rdpUser) -ForegroundColor Gray
        }
    }
    Write-Host ''

    if ($OutputPath) {
        $htmlDir = $OutputPath
        New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
        $htmlPath = Join-Path $htmlDir ("DeployReport-{0}.html" -f $dateStamp)

        $machineRows = ($Machines | ForEach-Object {
            $statusClass = switch ($_.Status) { 'OK' { 'ok' } 'WARN' { 'warn' } default { 'fail' } }
            ('        <tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f $statusClass, $_.VMName, $_.OSTag, $_.IP, (($_.Roles) -join ', '), $_.Status)
        }) -join "`n"

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Lab Deployment Report - $LabName</title>
<style>
  body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 40px; background: #1e1e2e; color: #cdd6f4; }
  h1 { color: #89b4fa; border-bottom: 2px solid #45475a; padding-bottom: 10px; }
  .meta { color: #a6adc8; margin-bottom: 20px; }
  .meta span { display: inline-block; margin-right: 30px; }
  table { border-collapse: collapse; width: 100%; margin-top: 20px; }
  th { background: #313244; color: #cba6f7; padding: 10px 15px; text-align: left; }
  td { padding: 8px 15px; border-bottom: 1px solid #45475a; }
  tr.ok td:last-child { color: #a6e3a1; font-weight: bold; }
  tr.warn td:last-child { color: #f9e2af; font-weight: bold; }
  tr.fail td:last-child { color: #f38ba8; font-weight: bold; }
  .footer { margin-top: 30px; color: #6c7086; font-size: 0.85em; }
</style>
</head>
<body>
  <h1>Lab Deployment Report</h1>
  <div class="meta">
    <span>Lab: <strong>$LabName</strong></span>
    <span>Date: <strong>$timestamp</strong></span>
    <span>Duration: <strong>$durationStr</strong></span>
    <span>Machines: <strong>$($Machines.Count)</strong></span>
  </div>
  <table>
    <thead>
      <tr><th>VM Name</th><th>OS</th><th>IP</th><th>Role(s)</th><th>Status</th></tr>
    </thead>
    <tbody>
$machineRows
    </tbody>
  </table>
  <div class="footer">Generated by LabBuilder on $timestamp</div>
</body>
</html>
"@

        [IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($false))
        Write-Host ("  Report saved: {0}" -f $htmlPath) -ForegroundColor Green
        return $htmlPath
    }

    return $null
}

#endregion Reporting

#region Backward-Compatible Aliases

Set-Alias -Name Remove-VMHardSafe -Value Remove-HyperVVMStale

# Backward-compatible aliases (permanent -- never remove)
Set-Alias -Name Get-LIN1IPv4               -Value Get-LinuxVMIPv4
Set-Alias -Name Get-LIN1DhcpLeaseIPv4      -Value Get-LinuxVMDhcpLeaseIPv4
Set-Alias -Name Invoke-BashOnLIN1          -Value Invoke-BashOnLinuxVM
Set-Alias -Name New-LIN1VM                 -Value New-LinuxVM
Set-Alias -Name Finalize-LIN1InstallMedia  -Value Finalize-LinuxInstallMedia

# Standard-name aliases (Ensure- -> Test-Lab pattern)
Set-Alias -Name Test-LabVMRunning        -Value Ensure-VMRunning
Set-Alias -Name Test-LabVMsReady         -Value Ensure-VMsReady
Set-Alias -Name Test-LabSSHKey           -Value Ensure-SSHKey

#endregion Backward-Compatible Aliases
