# Configure-LIN1.ps1 - Post-deploy LIN1 SSH bootstrap/config helper
# Use this when DC1/WS1 are already deployed and LIN1 exists but timed out during AutomatedLab wait.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$AdminPassword = '$Server123!'
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($AdminPassword) -and $env:OPENCODELAB_ADMIN_PASSWORD) {
    $AdminPassword = $env:OPENCODELAB_ADMIN_PASSWORD
}
if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    $AdminPassword = '$Server123!'
    Write-Host "  [WARN] AdminPassword was empty. Falling back to default password." -ForegroundColor Yellow
}

if (-not (Import-OpenCodeLab -Name $LabName)) {
    throw "Lab '$LabName' is not imported. Run deploy first."
}

$lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
if (-not $lin1Vm) {
    throw "LIN1 VM not found. Create LIN1 first (e.g. Deploy.ps1 -IncludeLIN1), then re-run Configure-LIN1.ps1."
}
if ($lin1Vm.State -ne 'Running') {
    Start-VM -Name 'LIN1' | Out-Null
}

Write-Host "[LIN1] Waiting for SSH reachability (up to 30 min)..." -ForegroundColor Cyan
$lin1Ready = $false
$lin1Deadline = [datetime]::Now.AddMinutes(30)
while ([datetime]::Now -lt $lin1Deadline) {
    $lin1Ips = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }
    if ($lin1Ips) {
        $lin1DhcpIp = $lin1Ips | Select-Object -First 1
        $sshCheck = Test-NetConnection -ComputerName $lin1DhcpIp -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($sshCheck.TcpTestSucceeded) {
            $lin1Ready = $true
            break
        }
    }
    Start-Sleep -Seconds 30
}
if (-not $lin1Ready) {
    throw "LIN1 is not SSH reachable yet. Finish Ubuntu install/reboot, then run Configure-LIN1.ps1 again."
}

$HostPublicKeyFileName = [System.IO.Path]::GetFileName($SSHPublicKey)
Copy-LabFileItem -Path $SSHPublicKey -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

$linUser = $LinuxUser
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
Invoke-BashOnLIN1 -BashScript $script -ActivityName 'Configure-LIN1-PostDeploy' -Variables $vars | Out-Null

Write-Host "[OK] LIN1 SSH bootstrap complete." -ForegroundColor Green
