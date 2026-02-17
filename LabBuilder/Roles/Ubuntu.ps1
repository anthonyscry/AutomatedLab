function Get-LabRole_Ubuntu {
    <#
    .SYNOPSIS
        Returns the Ubuntu Linux role definition for LabBuilder.
    .DESCRIPTION
        Defines LIN1 as an Ubuntu 24.04 Linux VM. Unlike Windows roles,
        Linux VMs bypass AutomatedLab's Install-Lab and are created manually
        using Hyper-V cmdlets + cloud-init autoinstall via CIDATA VHDX.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    # Null-guard: LinuxVM config required
    if (-not $Config.ContainsKey('LinuxVM') -or -not $Config.LinuxVM) {
        Write-Warning "Linux VM configuration not found. Skipping role definition for Ubuntu."
        return @{ Tag = 'Ubuntu'; VMName = ''; SkipInstallLab = $true; IsLinux = $true; Roles = @(); OS = ''; IP = ''; Gateway = ''; DnsServer1 = ''; PostInstall = $null; CreateVM = $null }
    }

    # Dot-source Lab-Common.ps1 for Linux helper functions
    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    $linuxRoleBasePath = Join-Path $PSScriptRoot 'LinuxRoleBase.ps1'
    if (Test-Path $linuxRoleBasePath) { . $linuxRoleBasePath }

    return @{
        Tag            = 'Ubuntu'
        VMName         = $Config.VMNames.Ubuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.Ubuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            Invoke-LinuxRoleCreateVM -LabConfig $LabConfig -VMNameKey 'Ubuntu'
        }

        PostInstall = {
            param([hashtable]$LabConfig)

            $script = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[POST] Updating packages..."
`$SUDO apt-get update -qq || true
`$SUDO apt-get install -y -qq openssh-server cifs-utils net-tools curl wget git jq build-essential || true

echo "[POST] Configuring SSH..."
`$SUDO systemctl enable --now ssh || true

echo "[POST] Installing dev tools..."
`$SUDO apt-get install -y -qq python3 python3-pip nodejs npm 2>/dev/null || true

echo "[POST] Post-install complete."
"@

            Invoke-LinuxRolePostInstall -LabConfig $LabConfig -VMNameKey 'Ubuntu' -BashScript $script
        }
    }
}
