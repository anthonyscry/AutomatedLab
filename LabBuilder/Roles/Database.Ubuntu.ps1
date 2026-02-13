function Get-LabRole_DatabaseUbuntu {
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
        Tag            = 'DatabaseUbuntu'
        VMName         = $Config.VMNames.DatabaseUbuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.DatabaseUbuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            Invoke-LinuxRoleCreateVM -LabConfig $LabConfig -VMNameKey 'DatabaseUbuntu'
        }

        PostInstall = {
            param([hashtable]$LabConfig)

            $script = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

DB_NAME="labdb"
DB_USER="labuser"
DB_PASS="LabDB123!"

echo "[Database] Installing PostgreSQL..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq postgresql postgresql-contrib
`$SUDO systemctl enable --now postgresql

echo "[Database] Configuring database and role..."
`$SUDO -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='`$DB_USER';" | grep -q 1 || `$SUDO -u postgres psql -c "CREATE ROLE `$DB_USER LOGIN PASSWORD '`$DB_PASS';"
`$SUDO -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='`$DB_NAME';" | grep -q 1 || `$SUDO -u postgres psql -c "CREATE DATABASE `$DB_NAME OWNER `$DB_USER;"

echo "[Database] PostgreSQL installed and labdb ready."
"@

            Invoke-LinuxRolePostInstall -LabConfig $LabConfig -VMNameKey 'DatabaseUbuntu' -BashScript $script -SuccessMessage 'PostgreSQL installed'
        }
    }
}
