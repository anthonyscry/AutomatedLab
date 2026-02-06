<#
.SYNOPSIS
    Deploy-OpenCodeLab-Slim.ps1 — Rebuildable 3‑VM OpenCode Development Lab (AutomatedLab)

.DESCRIPTION
    Builds a deterministic 3‑VM lab on Hyper‑V using AutomatedLab:

      DC1  — Windows Server 2019 (AD DS, DNS, CA) + DHCP (for Linux) + SMB share + Git
      WS1  — Windows 11 Enterprise Evaluation (domain-joined AppLocker test target)
      LIN1 — Ubuntu Server 24.04.x (domain DNS, SSH keys, dev tooling, SMB mount)

    Key pain this version fixes:
      - Linux network config no longer blocks install: DC1 is installed FIRST, then DHCP scope is created,
        then WS1/LIN1 install. This prevents the Ubuntu installer "autoconfiguration failed" screen.
      - Linux user is deterministic: we use a lowercase lab install user ("install") everywhere.
      - Host-to-LIN1 SSH uses a lab keypair generated on the Hyper‑V host (no GitHub import/paste).

.NOTES
    Author:  Tony / Assistant
    Version: 3.2 (Rebuildable / DHCP-first / Linux user fixed)
    Requires: AutomatedLab module, Hyper-V, ISOs in C:\LabSources\ISOs
#>

#Requires -RunAsAdministrator
#Requires -Modules AutomatedLab

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$ForceRebuild,
    [string]$AdminPassword = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ============================================================
# CONFIGURATION — EDIT IF YOU WANT DIFFERENT IPs / NAMES
# ============================================================
$LabName        = 'OpenCodeLab'
$DomainName     = 'opencode.lab'

# Deterministic lab install user (Windows is case-insensitive; Linux is not)
$LabInstallUser = 'install'
if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    if ($env:OPENCODELAB_ADMIN_PASSWORD) {
        $AdminPassword = $env:OPENCODELAB_ADMIN_PASSWORD
    }
}
if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    throw "AdminPassword is required. Provide -AdminPassword or set OPENCODELAB_ADMIN_PASSWORD."
}

$LabPath        = "C:\AutomatedLab\$LabName"
$LabSourcesRoot = 'C:\LabSources'
$IsoPath        = "$LabSourcesRoot\ISOs"

# Networking: dedicated Internal vSwitch + host NAT
$LabSwitch    = 'OpenCodeLabSwitch'
$AddressSpace = '192.168.11.0/24'
$GatewayIp    = '192.168.11.1'
$NatName      = "${LabSwitch}NAT"

# Static IP plan
$DC1_Ip  = '192.168.11.3'
$WS1_Ip  = '192.168.11.4'
$LIN1_Ip = '192.168.11.5'   # we will set static AFTER install (install uses DHCP)

$DnsIp   = $DC1_Ip

# DHCP scope for the lab subnet (keeps .1-.99 free for statics)
$DhcpScopeId = '192.168.11.0'
$DhcpStart   = '192.168.11.100'
$DhcpEnd     = '192.168.11.200'
$DhcpMask    = '255.255.255.0'

# VM sizing
$DC_Memory      = 4GB
$DC_MinMemory   = 2GB
$DC_MaxMemory   = 6GB
$DC_Processors  = 4

$CL_Memory      = 4GB
$CL_MinMemory   = 2GB
$CL_MaxMemory   = 6GB
$CL_Processors  = 4

$UBU_Memory     = 4GB
$UBU_MinMemory  = 2GB
$UBU_MaxMemory  = 6GB
$UBU_Processors = 4

# Share settings (hosted on DC1)
$ShareName   = 'LabShare'
$SharePath   = 'C:\LabShare'
$GitRepoPath = 'C:\LabShare\Repos'

# SSH keypair (generated on the Hyper‑V host; used for Host -> LIN1 and Host -> DC1)
$SSHKeyDir     = "$LabSourcesRoot\SSHKeys"
$SSHPrivateKey = "$SSHKeyDir\id_ed25519"
$SSHPublicKey  = "$SSHKeyDir\id_ed25519.pub"
$HostPublicKeyFileName = [System.IO.Path]::GetFileName($SSHPublicKey)

function Invoke-WindowsSshKeygen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrivateKeyPath,
        [Parameter()][string]$Comment = ""
    )

    $sshExe = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"
    if (-not (Test-Path $sshExe)) {
        throw "OpenSSH ssh-keygen not found at $sshExe. Install Windows optional feature: OpenSSH Client."
    }

    $priv = $PrivateKeyPath
    $pub  = "$PrivateKeyPath.pub"
    $dir = Split-Path -Parent $priv
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    # cmd.exe avoids PowerShell native-arg quoting weirdness
    $cmd = '"' + $sshExe + '" -t ed25519 -f "' + $priv + '" -N ""'
    if ($Comment -and $Comment.Trim().Length -gt 0) {
        $cmd += ' -C "' + $Comment.Replace('"','\"') + '"'
    }

    & $env:ComSpec /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed (exit code $LASTEXITCODE)." }
    if (-not (Test-Path $priv) -or -not (Test-Path $pub)) {
        throw "ssh-keygen reported success but key files were not found: $priv / $pub"
    }
}

# ============================================================
# LOGGING
# ============================================================
$logDir  = "$LabSourcesRoot\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = "$logDir\Deploy-OpenCodeLab-Slim_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
    Write-Host "`n[PRE-FLIGHT] Checking ISOs..." -ForegroundColor Cyan
    $requiredISOs = @('server2019.iso', 'win11.iso', 'ubuntu-24.04.3.iso')
    $missing = @()
    foreach ($iso in $requiredISOs) {
        $p = Join-Path $IsoPath $iso
        if (Test-Path $p) { Write-Host "  [OK] $iso" -ForegroundColor Green }
        else { Write-Host "  [MISSING] $iso" -ForegroundColor Red; $missing += $iso }
    }
    if ($missing.Count -gt 0) {
        throw "Missing ISOs in ${IsoPath}: $($missing -join ', ')"
    }

    # Remove existing lab if present
    if (Get-Lab -List | Where-Object { $_ -eq $LabName }) {
        Write-Host "  Lab '$LabName' already exists." -ForegroundColor Yellow
        $allowRebuild = $false
        if ($ForceRebuild -or $NonInteractive) {
            $allowRebuild = $true
        } else {
            $response = Read-Host "  Remove and rebuild? (y/n)"
            if ($response -eq 'y') { $allowRebuild = $true }
        }

        if ($allowRebuild) {
            Remove-Lab -Name $LabName -Confirm:$false
            Write-Host "  Removed existing lab." -ForegroundColor Green
        } else {
            throw "Aborting by user choice."
        }
    }

    # Ensure SSH keypair exists
    if (-not (Test-Path $SSHPrivateKey) -or -not (Test-Path $SSHPublicKey)) {
        Write-Host "  Generating host SSH keypair..." -ForegroundColor Yellow
        Invoke-WindowsSshKeygen -PrivateKeyPath $SSHPrivateKey -Comment "lab-opencode"
        Write-Host "  SSH keypair ready at $SSHKeyDir" -ForegroundColor Green
    } else {
        Write-Host "  SSH keypair found: $SSHPrivateKey" -ForegroundColor Green
    }

    # ============================================================
    # LAB DEFINITION
    # ============================================================
    Write-Host "`n[LAB] Defining lab '$LabName'..." -ForegroundColor Cyan

    New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath $LabPath

    # Ensure vSwitch + NAT exist (idempotent)
    Write-Host "  Ensuring Hyper-V lab switch + NAT ($LabSwitch / $AddressSpace)..." -ForegroundColor Yellow

    if (-not (Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name $LabSwitch -SwitchType Internal | Out-Null
        Write-Host "    [OK] Created VMSwitch: $LabSwitch (Internal)" -ForegroundColor Green
    } else {
        Write-Host "    [OK] VMSwitch exists: $LabSwitch" -ForegroundColor Green
    }

    $ifAlias = "vEthernet ($LabSwitch)"
    $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -eq $GatewayIp }
    if (-not $hasGw) {
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
        Write-Host "    [OK] Set host gateway IP: $GatewayIp on $ifAlias" -ForegroundColor Green
    } else {
        Write-Host "    [OK] Host gateway IP already set: $GatewayIp" -ForegroundColor Green
    }

    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-Host "    [OK] Created NAT: $NatName for $AddressSpace" -ForegroundColor Green
    } elseif ($nat.InternalIPInterfaceAddressPrefix -ne $AddressSpace) {
        Write-Host "    [WARN] NAT '$NatName' exists with prefix '$($nat.InternalIPInterfaceAddressPrefix)'. Recreating..." -ForegroundColor Yellow
        Remove-NetNat -Name $NatName -Confirm:$false | Out-Null
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-Host "    [OK] Recreated NAT: $NatName for $AddressSpace" -ForegroundColor Green
    } else {
        Write-Host "    [OK] NAT exists: $NatName" -ForegroundColor Green
    }

    # Register network with AutomatedLab
    Add-LabVirtualNetworkDefinition -Name $LabSwitch -AddressSpace $AddressSpace -HyperVProperties @{ SwitchType = 'Internal' }

    # Use the deterministic install credential everywhere
    Set-LabInstallationCredential -Username $LabInstallUser -Password $AdminPassword
    Add-LabDomainDefinition -Name $DomainName -AdminUser $LabInstallUser -AdminPassword $AdminPassword

    # ============================================================
    # STAGE 1: DC1 ONLY (so we can stand up DHCP before Linux)
    # ============================================================
    Write-Host "`n[STAGE 1] Installing DC1 first (AD/DNS/CA)..." -ForegroundColor Cyan

    Add-LabMachineDefinition -Name 'DC1' `
        -Roles RootDC, CaRoot `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $DC1_Ip -Gateway $GatewayIp -DnsServer1 $DC1_Ip `
        -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
        -Memory $DC_Memory -MinMemory $DC_MinMemory -MaxMemory $DC_MaxMemory `
        -Processors $DC_Processors

    Install-Lab -Machines DC1

    # ============================================================
    # DC1: DHCP ROLE + SCOPE
    # ============================================================
    Write-Host "`n[DC1] Enabling DHCP for Linux installs (prevents Ubuntu DHCP/autoconfig failure)..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Install-DHCP-Role' -ScriptBlock {
        param($ScopeId, $StartRange, $EndRange, $Mask, $Router, $Dns, $DnsDomain)

        # Install DHCP role
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null

        # Authorize DHCP in AD (ignore if already authorized)
        try {
            if ($Dns) { Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -IPAddress $Dns | Out-Null }
        } catch {}

        # Create scope if missing
        $existing = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId.IPAddressToString -eq $ScopeId }
        if (-not $existing) {
            Add-DhcpServerv4Scope -Name "OpenCodeLab" -StartRange $StartRange -EndRange $EndRange -SubnetMask $Mask -State Active | Out-Null
        }

        # Options
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -DnsServer @($Dns,'1.1.1.1') -DnsDomain $DnsDomain | Out-Null

        Restart-Service DHCPServer -ErrorAction SilentlyContinue
        Set-Service DHCPServer -StartupType Automatic

        "DHCP scope ready"
    } -ArgumentList $DhcpScopeId, $DhcpStart, $DhcpEnd, $DhcpMask, $GatewayIp, $DnsIp, $DomainName | Out-Null

    Write-Host "  [OK] DHCP scope configured: $DhcpScopeId ($DhcpStart - $DhcpEnd)" -ForegroundColor Green

    # ============================================================
    # STAGE 2: WS1 + LIN1
    # ============================================================
    Write-Host "`n[STAGE 2] Installing WS1 + LIN1..." -ForegroundColor Cyan

    Add-LabMachineDefinition -Name 'WS1' `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $WS1_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
        -OperatingSystem 'Windows 11 Enterprise Evaluation' `
        -Memory $CL_Memory -MinMemory $CL_MinMemory -MaxMemory $CL_MaxMemory `
        -Processors $CL_Processors

    Add-LabMachineDefinition -Name 'LIN1' `
        -Network $LabSwitch `
        -OperatingSystem 'Ubuntu-Server 24.04.3 LTS "Noble Numbat"' `
        -Memory $UBU_Memory -MinMemory $UBU_MinMemory -MaxMemory $UBU_MaxMemory `
        -Processors $UBU_Processors

    Install-Lab -Machines WS1, LIN1

    # ============================================================
    # POST-INSTALL: DC1 share + Git
    # ============================================================
    Write-Host "`n[POST] Configuring DC1 share + Git..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Create-LabShare' -ScriptBlock {
        param($SharePath, $ShareName, $GitRepoPath, $DomainName)

        New-Item -Path $SharePath -ItemType Directory -Force | Out-Null
        New-Item -Path $GitRepoPath -ItemType Directory -Force | Out-Null
        New-Item -Path "$SharePath\Transfer" -ItemType Directory -Force | Out-Null
        New-Item -Path "$SharePath\Tools" -ItemType Directory -Force | Out-Null

        $netbios = ($DomainName -split '\.')[0].ToUpper()
        try {
            New-ADGroup -Name 'LabShareUsers' -GroupScope DomainLocal -Path "CN=Users,DC=$($DomainName -replace '\.',',DC=')" -ErrorAction Stop | Out-Null
        } catch {}

        try { Add-ADGroupMember -Identity 'LabShareUsers' -Members 'Domain Users' -ErrorAction SilentlyContinue } catch {}

        try {
            if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
                New-SmbShare -Name $ShareName -Path $SharePath `
                    -FullAccess "$netbios\LabShareUsers", "$netbios\Domain Admins" `
                    -Description 'OpenCode Lab Shared Storage' | Out-Null
            }
        } catch {}

        $acl = Get-Acl $SharePath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$netbios\LabShareUsers", 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl $SharePath $acl

        "Share ready"
    } -ArgumentList $SharePath, $ShareName, $GitRepoPath, $DomainName | Out-Null

    # Add WS1$ to share group (after join)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Add-WS1-To-ShareGroup' -ScriptBlock {
        try { Add-ADGroupMember -Identity 'LabShareUsers' -Members 'WS1$' -ErrorAction Stop | Out-Null } catch {}
    } | Out-Null

    # Install Git on DC1 (winget if available, else direct)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Install-Git-DC1' -ScriptBlock {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            winget install --id Git.Git --accept-package-agreements --accept-source-agreements --silent 2>$null
        } else {
            $gitUrl = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe'
            $gitInstaller = "$env:TEMP\GitInstall.exe"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
            Start-Process -FilePath $gitInstaller -ArgumentList '/VERYSILENT /NORESTART /COMPONENTS="gitlfs"' -Wait -NoNewWindow
            Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null

    # ============================================================
    # DC1: OpenSSH Server + allow key auth for admins (Host -> DC1)
    # ============================================================
    Write-Host "`n[POST] Configuring DC1 OpenSSH..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Install-OpenSSH-DC1' -ScriptBlock {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
        Set-Service -Name sshd -StartupType Automatic
        Start-Service sshd
        New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
            -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
            -PropertyType String -Force | Out-Null
        New-NetFirewallRule -DisplayName 'OpenSSH Server (TCP 22)' -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    } | Out-Null

    Copy-LabFileItem -Path $SSHPublicKey -ComputerName 'DC1' -DestinationFolderPath 'C:\ProgramData\ssh'

    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Authorize-HostKey-DC1' -ScriptBlock {
        param($PubKeyFileName)
        $authKeysFile = 'C:\ProgramData\ssh\administrators_authorized_keys'
        $pubKeyFile   = "C:\ProgramData\ssh\$PubKeyFileName"
        if (Test-Path $pubKeyFile) {
            Get-Content $pubKeyFile | Add-Content $authKeysFile -Force
            icacls $authKeysFile /inheritance:r /grant "SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)" | Out-Null
            Remove-Item $pubKeyFile -Force -ErrorAction SilentlyContinue
        }
    } -ArgumentList $HostPublicKeyFileName | Out-Null

    # DC1: WinRM HTTPS + ICMP (useful for remote management)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Configure-WinRM-HTTPS-DC1' -ScriptBlock {
        $fqdn = "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
        $cert = New-SelfSignedCertificate -DnsName $fqdn, $env:COMPUTERNAME -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)

        Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
            ForEach-Object { Remove-Item $_.PSPath -Recurse -Force }

        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

        New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName 'ICMPv4 Allow' -Protocol ICMPv4 -IcmpType 8 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue | Out-Null
    } | Out-Null


    # ============================================================
    # WS1: client basics (RSAT + drive map)
    # ============================================================
    Write-Host "`n[POST] Configuring WS1..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Install-RSAT-WS1' -ScriptBlock {
        $rsatCapabilities = @(
            'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0',
            'Rsat.Dns.Tools~~~~0.0.1.0',
            'Rsat.DHCP.Tools~~~~0.0.1.0',
            'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
        )
        foreach ($cap in $rsatCapabilities) {
            $state = (Get-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue).State
            if ($state -ne 'Installed') { Add-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue | Out-Null }
        }
        Set-Service -Name AppIDSvc -StartupType Automatic
        Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    } | Out-Null

    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Map-LabShare' -ScriptBlock {
        param($ShareName)
        net use L: "\\DC1\$ShareName" /persistent:yes 2>$null
    } -ArgumentList $ShareName | Out-Null

    # WS1: WinRM HTTPS + ICMP
    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Configure-WinRM-HTTPS-WS1' -ScriptBlock {
        $fqdn = "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
        $cert = New-SelfSignedCertificate -DnsName $fqdn, $env:COMPUTERNAME -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)

        Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
            ForEach-Object { Remove-Item $_.PSPath -Recurse -Force }

        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

        New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName 'ICMPv4 Allow' -Protocol ICMPv4 -IcmpType 8 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue | Out-Null
    } | Out-Null

    # WS1: Git (winget)
    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Install-Git-WS1' -ScriptBlock {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            winget install --id Git.Git --accept-package-agreements --accept-source-agreements --silent 2>$null
        }
    } | Out-Null


    # ============================================================
    # LIN1: deterministic user, SSH keys, static IP, SMB mount, dev tools
    # ============================================================
    Write-Host "`n[POST] Configuring LIN1 (Ubuntu dev host)..." -ForegroundColor Cyan

    $netbios = ($DomainName -split '\.')[0].ToUpper()
    $linUser = $LabInstallUser
    $linHome = "/home/$linUser"

    $lin1ScriptPath = "$LabSourcesRoot\lin1_setup.sh"
    $escapedPassword = $AdminPassword -replace "'", "'\\''"

    $lin1ScriptContent = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

# Pick the first non-lo interface (installer often shows eth0, but this is safer)
IFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
if [ -z "$IFACE" ]; then IFACE="eth0"; fi

LIN_USER="$linUser"
LIN_HOME="$linHome"
DOMAIN="$DomainName"
NETBIOS="$netbios"
SHARE="$ShareName"
PASS='$escapedPassword'
GATEWAY="$GatewayIp"
DNS="$DnsIp"
STATIC_IP="$LIN1_Ip"

echo "[LIN1] Updating packages..."
$SUDO apt-get update -qq

echo "[LIN1] Installing base tools + OpenSSH..."
$SUDO apt-get install -y -qq \
  openssh-server git curl wget jq cifs-utils net-tools build-essential python3 python3-pip \
  nodejs npm 2>/dev/null || true

$SUDO systemctl enable --now ssh || true

# Ensure SSH allows password auth (optional; helps if you ever need it)
$SUDO tee /etc/ssh/sshd_config.d/99-opencodelab.conf >/dev/null <<'EOF'
PasswordAuthentication yes
PubkeyAuthentication yes
EOF
$SUDO systemctl restart ssh || true

echo "[LIN1] Setting up SSH authorized_keys for ${LIN_USER}..."
mkdir -p "$LIN_HOME/.ssh"
chmod 700 "$LIN_HOME/.ssh"
touch "$LIN_HOME/.ssh/authorized_keys"
chmod 600 "$LIN_HOME/.ssh/authorized_keys"

if [ -f /tmp/$HostPublicKeyFileName ]; then
  cat /tmp/$HostPublicKeyFileName >> "$LIN_HOME/.ssh/authorized_keys" || true
fi

chown -R "${LIN_USER}:${LIN_USER}" "$LIN_HOME/.ssh"

echo "[LIN1] Generating local SSH keypair (LIN1->DC1)..."
sudo -u "$LIN_USER" bash -lc 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "LIN1-to-DC1"'

echo "[LIN1] Configuring SMB mount..."
$SUDO mkdir -p /mnt/labshare
CREDS_FILE="/etc/opencodelab-labshare.cred"
if [ ! -f "$CREDS_FILE" ]; then
  $SUDO tee "$CREDS_FILE" >/dev/null <<EOF
username=$LIN_USER
password=$PASS
domain=$NETBIOS
EOF
  $SUDO chmod 600 "$CREDS_FILE"
fi
FSTAB_ENTRY="//DC1.$DOMAIN/$SHARE /mnt/labshare cifs credentials=$CREDS_FILE,iocharset=utf8,_netdev 0 0"
if ! grep -qF "DC1.$DOMAIN/$SHARE" /etc/fstab 2>/dev/null; then
  echo "$FSTAB_ENTRY" | $SUDO tee -a /etc/fstab >/dev/null
fi
$SUDO mount -a 2>/dev/null || true

echo "[LIN1] Pinning static IP ($STATIC_IP) for stable SSH..."
$SUDO tee /etc/netplan/99-opencodelab-static.yaml >/dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [$STATIC_IP/24]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS, 1.1.1.1]
EOF

# Apply netplan in the background so we don't hang the remote session mid-flight
(sleep 2; $SUDO netplan apply) >/dev/null 2>&1 &

echo "[LIN1] Done."
"@

    $lin1ScriptContent | Set-Content -Path $lin1ScriptPath -Encoding ASCII -Force

    Copy-LabFileItem -Path $SSHPublicKey -ComputerName 'LIN1' -DestinationFolderPath '/tmp'
    Copy-LabFileItem -Path $lin1ScriptPath -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

    Invoke-LabCommand -ComputerName 'LIN1' -ActivityName 'Configure-LIN1' -ScriptBlock {
        chmod +x /tmp/lin1_setup.sh
        bash /tmp/lin1_setup.sh
    } | Out-Null

    # ============================================================
    # SNAPSHOT
    # ============================================================
    Write-Host "`n[SNAPSHOT] Creating 'LabReady' checkpoint..." -ForegroundColor Cyan
    Checkpoint-LabVM -All -SnapshotName 'LabReady' | Out-Null
    Write-Host "  Checkpoint created." -ForegroundColor Green

    # ============================================================
    # SUMMARY
    # ============================================================
    Write-Host "`n[SUMMARY]" -ForegroundColor Cyan
    Write-Host "  DC1:  $DC1_Ip" -ForegroundColor Gray
    Write-Host "  WS1:  $WS1_Ip" -ForegroundColor Gray
    Write-Host "  LIN1: $LIN1_Ip (static configured by script)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Host -> LIN1 SSH:" -ForegroundColor Cyan
    Write-Host "    ssh -o IdentitiesOnly=yes -i $SSHPrivateKey $LabInstallUser@$LIN1_Ip" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If you see the 'REMOTE HOST IDENTIFICATION HAS CHANGED' warning after a rebuild:" -ForegroundColor Cyan
    Write-Host "    ssh-keygen -R $LIN1_Ip" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "DONE. Log saved to: $logFile" -ForegroundColor Green
}
catch {
    Write-Host "`nDEPLOYMENT FAILED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nSee log: $logFile" -ForegroundColor Yellow
}
finally {
    Stop-Transcript | Out-Null
}
