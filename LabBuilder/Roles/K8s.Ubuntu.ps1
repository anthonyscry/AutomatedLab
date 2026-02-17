function Get-LabRole_K8sUbuntu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    # Null-guard: LinuxVM config required
    if (-not $Config.ContainsKey('LinuxVM') -or -not $Config.LinuxVM) {
        Write-Warning "Linux VM configuration not found. Skipping role definition for K8sUbuntu."
        return @{ Tag = 'K8sUbuntu'; VMName = ''; SkipInstallLab = $true; IsLinux = $true; Roles = @(); OS = ''; IP = ''; Gateway = ''; DnsServer1 = ''; PostInstall = $null; CreateVM = $null }
    }

    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    $linuxRoleBasePath = Join-Path $PSScriptRoot 'LinuxRoleBase.ps1'
    if (Test-Path $linuxRoleBasePath) { . $linuxRoleBasePath }

    return @{
        Tag            = 'K8sUbuntu'
        VMName         = $Config.VMNames.K8sUbuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.K8sUbuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            Invoke-LinuxRoleCreateVM -LabConfig $LabConfig -VMNameKey 'K8sUbuntu'
        }

        PostInstall = {
            param([hashtable]$LabConfig)

            $script = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[K8s] Installing dependencies..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq curl ca-certificates

echo "[K8s] Installing k3s (single-node server)..."
curl -sfL https://get.k3s.io | `$SUDO sh -

echo "[K8s] Waiting for node to become Ready..."
for i in `$(seq 1 60); do
    if `$SUDO k3s kubectl get nodes 2>/dev/null | grep -q ' Ready '; then
        break
    fi
    sleep 5
done

`$SUDO systemctl enable --now k3s
`$SUDO mkdir -p /home/$linuxUser/.kube
`$SUDO cp /etc/rancher/k3s/k3s.yaml /home/$linuxUser/.kube/config
`$SUDO chown -R ${linuxUser}:${linuxUser} /home/$linuxUser/.kube

echo "[K8s] Node status:"
`$SUDO k3s kubectl get nodes -o wide || true
echo "[K8s] k3s installation complete."
"@

            Invoke-LinuxRolePostInstall -LabConfig $LabConfig -VMNameKey 'K8sUbuntu' -BashScript $script -SuccessMessage 'k3s installed'
        }
    }
}
