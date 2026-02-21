function Get-LabRole_CentOS {
    <#
    .SYNOPSIS
        Returns the CentOS Stream Linux role definition for LabBuilder.
    .DESCRIPTION
        Defines LINCENT1 as a CentOS Stream 9 Linux VM. Like Ubuntu, CentOS VMs
        bypass AutomatedLab's Install-Lab and are created manually using Hyper-V
        cmdlets + cloud-init NoCloud datasource via CIDATA VHDX.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    # Null-guard: LinuxVM config required
    if (-not $Config.ContainsKey('LinuxVM') -or -not $Config.LinuxVM) {
        Write-Warning "Linux VM configuration not found. Skipping role definition for CentOS."
        return @{ Tag = 'CentOS'; VMName = ''; SkipInstallLab = $true; IsLinux = $true; Roles = @(); OS = ''; IP = ''; Gateway = ''; DnsServer1 = ''; PostInstall = $null; CreateVM = $null }
    }

    # Dot-source Lab-Common.ps1 for Linux helper functions
    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    $linuxRoleBasePath = Join-Path $PSScriptRoot 'LinuxRoleBase.ps1'
    if (Test-Path $linuxRoleBasePath) { . $linuxRoleBasePath }

    return @{
        Tag            = 'CentOS'
        VMName         = $Config.VMNames.CentOS
        IsLinux        = $true
        SkipInstallLab = $true
        OS             = 'CentOS Stream 9'
        Memory         = $Config.LinuxVM.Memory
        MinMemory      = $Config.LinuxVM.MinMemory
        MaxMemory      = $Config.LinuxVM.MaxMemory
        Processors     = $Config.LinuxVM.Processors
        IP             = $Config.IPPlan.CentOS
        Gateway        = $Config.Network.Gateway
        DnsServer1     = $Config.IPPlan.DC
        Network        = $Config.Network.SwitchName
        DomainName     = $Config.DomainName
        Roles          = @()

        CreateVM = {
            param([hashtable]$LabConfig)
            Invoke-LinuxRoleCreateVM -LabConfig $LabConfig -VMNameKey 'CentOS' -ISOPattern 'CentOS-Stream-9*.iso'
        }

        PostInstall = {
            param([hashtable]$LabConfig)
            $script = @"
#!/bin/bash
set -e
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[POST] Updating packages..."
`$SUDO dnf update -y -q || true
`$SUDO dnf install -y -q openssh-server cifs-utils net-tools curl wget git jq gcc make || true

echo "[POST] Configuring SSH..."
`$SUDO systemctl enable --now sshd || true

echo "[POST] Installing dev tools..."
`$SUDO dnf install -y -q python3 python3-pip nodejs npm 2>/dev/null || true

echo "[POST] Post-install complete."
"@
            Invoke-LinuxRolePostInstall -LabConfig $LabConfig -VMNameKey 'CentOS' -BashScript $script
        }
    }
}
