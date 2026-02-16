# Configure-LIN1.ps1 - Post-deploy LIN1 SSH bootstrap/config helper
# Use this when DC1/WS1 are already deployed and LIN1 exists but timed out during AutomatedLab wait.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$AdminPassword
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $RepoRoot 'Lab-Config.ps1'
$CommonPath = Join-Path $RepoRoot 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

$ErrorActionPreference = 'Stop'

# Password resolution: -AdminPassword param → Lab-Config.ps1 → env var → error
$AdminPassword = Resolve-LabPassword -Password $AdminPassword

if (-not (Import-OpenCodeLab -Name $GlobalLabConfig.Lab.Name)) {
    throw "Lab '$GlobalLabConfig.Lab.Name' is not imported. Run deploy first."
}

$lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
if (-not $lin1Vm) {
    throw "LIN1 VM not found. Create LIN1 first (e.g. Deploy.ps1 -IncludeLIN1), then re-run Configure-LIN1.ps1."
}
if ($lin1Vm.State -ne 'Running') {
    Start-VM -Name 'LIN1' | Out-Null
}

Write-Host "[LIN1] Waiting for SSH reachability (up to 30 min)..." -ForegroundColor Cyan
$lin1WaitResult = Wait-LinuxVMReady -VMName 'LIN1' -WaitMinutes $GlobalLabConfig.Timeouts.Linux.LIN1WaitMinutes -DhcpServer 'DC1' -ScopeId $GlobalLabConfig.DHCP.ScopeId
$lin1Ready = $lin1WaitResult.Ready
if (-not $lin1Ready) {
    if ($lin1WaitResult.LeaseIP) {
        Write-LabStatus -Status INFO -Message "LIN1 DHCP lease observed at: $($lin1WaitResult.LeaseIP)"
    }
    throw "LIN1 is not SSH reachable yet. Finish Ubuntu install/reboot, then run Configure-LIN1.ps1 again."
}

$HostPublicKeyFileName = [System.IO.Path]::GetFileName((Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub))
Copy-LabFileItem -Path (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub) -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

$linUser = if ([string]::IsNullOrWhiteSpace($GlobalLabConfig.Credentials.LinuxUser)) { 'anthonyscry' } else { $GlobalLabConfig.Credentials.LinuxUser }
$linHome = "/home/$linUser"
$escapedPassword = $AdminPassword -replace "'", "'\\''"

$script = @'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi
LIN_USER="__LIN_USER__"
LIN_HOME="__LIN_HOME__"
HOST_PUBKEY_FILE="__HOST_PUBKEY__"
PASS='__PASS__'

$SUDO apt-get update -qq || true
$SUDO apt-get install -y -qq openssh-server cifs-utils net-tools || true
$SUDO systemctl enable --now ssh || true

mkdir -p "$LIN_HOME/.ssh"
chmod 700 "$LIN_HOME/.ssh"
touch "$LIN_HOME/.ssh/authorized_keys"
chmod 600 "$LIN_HOME/.ssh/authorized_keys"
if [ -f "/tmp/$HOST_PUBKEY_FILE" ]; then
  cat "/tmp/$HOST_PUBKEY_FILE" >> "$LIN_HOME/.ssh/authorized_keys" || true
fi
chown -R "${LIN_USER}:${LIN_USER}" "$LIN_HOME/.ssh"

echo "$PASS" >/dev/null
'@

$vars = @{
    LIN_USER = $linUser
    LIN_HOME = $linHome
    HOST_PUBKEY = $HostPublicKeyFileName
    PASS = $escapedPassword
}
Invoke-BashOnLinuxVM -VMName 'LIN1' -BashScript $script -ActivityName 'Configure-LIN1-PostDeploy' -Variables $vars | Out-Null

Write-Host "[LIN1] Finalizing boot media (detach installer + seed disk)..." -ForegroundColor Cyan
Finalize-LinuxInstallMedia -VMName 'LIN1' | Out-Null

Write-LabStatus -Status OK -Message "LIN1 SSH bootstrap complete." -Indent 0
