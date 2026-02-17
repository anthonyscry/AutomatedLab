function Get-LabRole_WebServerUbuntu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    # Null-guard: LinuxVM config required
    if (-not $Config.ContainsKey('LinuxVM') -or -not $Config.LinuxVM) {
        Write-Warning "Linux VM configuration not found. Skipping role definition for WebServerUbuntu."
        return @{ Tag = 'WebServerUbuntu'; VMName = ''; SkipInstallLab = $true; IsLinux = $true; Roles = @(); OS = ''; IP = ''; Gateway = ''; DnsServer1 = ''; PostInstall = $null; CreateVM = $null }
    }

    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    $linuxRoleBasePath = Join-Path $PSScriptRoot 'LinuxRoleBase.ps1'
    if (Test-Path $linuxRoleBasePath) { . $linuxRoleBasePath }

    return @{
        Tag            = 'WebServerUbuntu'
        VMName         = $Config.VMNames.WebServerUbuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.WebServerUbuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            Invoke-LinuxRoleCreateVM -LabConfig $LabConfig -VMNameKey 'WebServerUbuntu'
        }

        PostInstall = {
            param([hashtable]$LabConfig)

            $script = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[WebServer] Installing nginx..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq nginx
`$SUDO systemctl enable --now nginx
`$SUDO bash -c 'cat > /var/www/html/index.html << HTMLEOF
<!DOCTYPE html><html><body><h1>LabBuilder WebServer - $vmName</h1><p>nginx running.</p></body></html>
HTMLEOF'
`$SUDO ufw allow 80/tcp 2>/dev/null || true
`$SUDO ufw allow 443/tcp 2>/dev/null || true
echo "[WebServer] nginx installed and running."
"@

            Invoke-LinuxRolePostInstall -LabConfig $LabConfig -VMNameKey 'WebServerUbuntu' -BashScript $script -SuccessMessage 'nginx installed'
        }
    }
}
