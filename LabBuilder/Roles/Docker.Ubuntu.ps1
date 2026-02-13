function Get-LabRole_DockerUbuntu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    $linuxRoleBasePath = Join-Path $PSScriptRoot 'LinuxRoleBase.ps1'
    if (Test-Path $linuxRoleBasePath) { . $linuxRoleBasePath }

    return @{
        Tag            = 'DockerUbuntu'
        VMName         = $Config.VMNames.DockerUbuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.DockerUbuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            Invoke-LinuxRoleCreateVM -LabConfig $LabConfig -VMNameKey 'DockerUbuntu'
        }

        PostInstall = {
            param([hashtable]$LabConfig)

            $script = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[Docker] Installing prerequisites..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release
`$SUDO install -m 0755 -d /etc/apt/keyrings
`$SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
`$SUDO chmod a+r /etc/apt/keyrings/docker.asc

echo "[Docker] Configuring Docker APT repository..."
ARCH=`$(dpkg --print-architecture)
CODENAME=`$(. /etc/os-release && echo "`${UBUNTU_CODENAME:-`$VERSION_CODENAME}")
echo "deb [arch=`$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu `$CODENAME stable" | `$SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "[Docker] Installing Docker CE + Compose plugin..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
`$SUDO systemctl enable --now docker
`$SUDO usermod -aG docker $linuxUser || true

echo "[Docker] Installed. docker --version:"
`$SUDO docker --version || true
echo "[Docker] Compose plugin version:"
`$SUDO docker compose version || true
"@

            Invoke-LinuxRolePostInstall -LabConfig $LabConfig -VMNameKey 'DockerUbuntu' -BashScript $script -SuccessMessage 'Docker installed'
        }
    }
}
