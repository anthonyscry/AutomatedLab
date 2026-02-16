# Join-LinuxToDomain.ps1 -- Join Linux VM to AD domain via SSSD
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
        [string]$GlobalLabConfig.Lab.DomainName = $(if ($GlobalLabConfig.Lab.DomainName) { $GlobalLabConfig.Lab.DomainName } else { 'simplelab.local' }),
        [string]$DomainAdmin = $(if ($GlobalLabConfig.Credentials.InstallUser) { $GlobalLabConfig.Credentials.InstallUser } else { 'Administrator' }),
        [string]$DomainPassword = $(if ($GlobalLabConfig.Credentials.AdminPassword) { $GlobalLabConfig.Credentials.AdminPassword } else { 'SimpleLab123!' }),
        [string]$User = $(if ($GlobalLabConfig.Credentials.LinuxUser) { $GlobalLabConfig.Credentials.LinuxUser } else { 'labadmin' }),
        [string]$KeyPath = $(if ((Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519)) { (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519) } else { 'C:\LabSources\SSHKeys\id_ed25519' }),
        [int]$SSHTimeout = $(if ($GlobalLabConfig.Timeouts.Linux.SSHConnectTimeout) { $GlobalLabConfig.Timeouts.Linux.SSHConnectTimeout } else { 8 })
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

echo "[SSSD] Discovering domain $GlobalLabConfig.Lab.DomainName..."
`$SUDO realm discover $GlobalLabConfig.Lab.DomainName

echo "[SSSD] Joining domain $GlobalLabConfig.Lab.DomainName..."
echo '$DomainPassword' | `$SUDO realm join -U $DomainAdmin $GlobalLabConfig.Lab.DomainName --install=/

echo "[SSSD] Configuring SSSD..."
`$SUDO bash -c 'cat > /etc/sssd/sssd.conf << SSSDEOF
[sssd]
domains = $GlobalLabConfig.Lab.DomainName
config_file_version = 2
services = nss, pam

[$('domain/' + $GlobalLabConfig.Lab.DomainName)]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = $($GlobalLabConfig.Lab.DomainName.ToUpperInvariant())
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = $GlobalLabConfig.Lab.DomainName
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

        Write-Host "    Joining $VMName to domain $GlobalLabConfig.Lab.DomainName via SSSD..." -ForegroundColor Cyan
        Invoke-LinuxSSH -IP $ip -Command 'chmod +x /tmp/domainjoin.sh && bash /tmp/domainjoin.sh && rm -f /tmp/domainjoin.sh' -User $User -KeyPath $KeyPath -ConnectTimeout $SSHTimeout

        Write-LabStatus -Status OK -Message "$VMName joined to $GlobalLabConfig.Lab.DomainName" -Indent 2
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
