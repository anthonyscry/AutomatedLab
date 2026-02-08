# Add-LIN1.ps1 - Add LIN1 to existing lab without reinstalling DC1/WS1
# Use this when DC1/WS1 are already deployed and you want to add LIN1

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$AdminPassword = 'Server123!'
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'

if (-not (Test-Path $ConfigPath)) {
    throw "Lab-Config.ps1 not found at: $ConfigPath"
}
if (-not (Test-Path $CommonPath)) {
    throw "Lab-Common.ps1 not found at: $CommonPath"
}

. $ConfigPath
. $CommonPath

$LabInstallUser = if ([string]::IsNullOrWhiteSpace($LinuxUser)) { 'anthonyscry' } else { $LinuxUser }

$ErrorActionPreference = 'Stop'

# Password handling
if ([string]::IsNullOrWhiteSpace($AdminPassword) -and $env:OPENCODELAB_ADMIN_PASSWORD) {
    $AdminPassword = $env:OPENCODELAB_ADMIN_PASSWORD
}
if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    $AdminPassword = 'Server123!'
    Write-Host "  [WARN] AdminPassword was empty. Falling back to default password." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Add LIN1 to Existing Lab" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Check if lab exists
if (-not (Import-OpenCodeLab -Name $LabName)) {
    throw "Lab '$LabName' is not imported. Run Deploy.ps1 first to create DC1/WS1."
}

# Check if DC1 and WS1 exist
$dc1 = Hyper-V\Get-VM -Name 'DC1' -ErrorAction SilentlyContinue
$ws1 = Hyper-V\Get-VM -Name 'WS1' -ErrorAction SilentlyContinue

if (-not $dc1 -or -not $ws1) {
    throw "DC1 or WS1 not found. Run Deploy.ps1 first to create the core lab."
}

Write-Host "[OK] Core lab (DC1/WS1) found" -ForegroundColor Green

# Check if LIN1 already exists
$existingLin1 = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
if ($existingLin1) {
    Write-Host "[WARN] LIN1 VM already exists!" -ForegroundColor Yellow
    if (-not $NonInteractive) {
        $response = Read-Host "Do you want to remove and recreate it? (yes/no)"
        if ($response -ne 'yes') {
            Write-Host "Aborted by user." -ForegroundColor Yellow
            exit 0
        }
    }
    Write-Host "  Removing existing LIN1..." -ForegroundColor Gray
    Remove-HyperVVMStale -VMName 'LIN1'
}

# Check for Ubuntu ISO
$IsoPath = "$LabSourcesRoot\ISOs"
$ubuntuIso = Get-ChildItem -Path $IsoPath -Filter 'ubuntu-24.04*.iso' -ErrorAction SilentlyContinue | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1 -ExpandProperty FullName

if (-not $ubuntuIso) {
    $ubuntuIso = Join-Path $IsoPath 'ubuntu-24.04.3.iso'
}

if (-not (Test-Path $ubuntuIso)) {
    Write-Host ""
    Write-Host "[ERROR] Ubuntu 24.04 ISO not found!" -ForegroundColor Red
    Write-Host "  Expected location: $ubuntuIso" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Download from: https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso" -ForegroundColor Cyan
    Write-Host "  Place at: C:\LabSources\ISOs\ubuntu-24.04.3.iso" -ForegroundColor Cyan
    Write-Host ""
    throw "Ubuntu ISO not found"
}

Write-Host "[OK] Ubuntu ISO found: $ubuntuIso" -ForegroundColor Green

# Create LIN1
Write-Host ""
Write-Host "[LIN1] Creating VM..." -ForegroundColor Cyan

try {
    # Generate password hash for autoinstall identity
    Write-Host "  Generating password hash..." -ForegroundColor Gray
    $lin1PwHash = Get-Sha512PasswordHash -Password $AdminPassword

    # Read SSH public key if available
    $lin1SshPubKey = ''
    if (Test-Path $SSHPublicKey) {
        $lin1SshPubKey = (Get-Content $SSHPublicKey -Raw).Trim()
        Write-Host "  SSH public key found" -ForegroundColor Gray
    }

    # Create CIDATA VHDX seed disk with autoinstall user-data
    $cidataPath = Join-Path $LabPath 'LIN1-cidata.vhdx'
    Write-Host "  Creating CIDATA seed disk with autoinstall config..." -ForegroundColor Gray
    New-CidataVhdx -OutputPath $cidataPath `
        -Hostname 'LIN1' `
        -Username $LabInstallUser `
        -PasswordHash $lin1PwHash `
        -SSHPublicKey $lin1SshPubKey

    # Create the LIN1 VM (Gen2, SecureBoot off, Ubuntu ISO + CIDATA VHDX)
    Write-Host "  Creating Hyper-V Gen2 VM..." -ForegroundColor Gray
    New-LIN1VM -UbuntuIsoPath $ubuntuIso -CidataVhdxPath $cidataPath | Out-Null

    # Start VM -- Ubuntu autoinstall should proceed unattended
    Start-VM -Name 'LIN1'
    Write-Host "  [OK] LIN1 VM started. Ubuntu autoinstall in progress..." -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] LIN1 VM creation failed: $($_.Exception.Message)" -ForegroundColor Red
    
    # Rollback: Clean up partial artifacts
    Write-Host "  Cleaning up partial LIN1 artifacts..." -ForegroundColor Gray
    Remove-VM -Name 'LIN1' -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $LabPath 'LIN1.vhdx') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $LabPath 'LIN1-cidata.vhdx') -Force -ErrorAction SilentlyContinue
    
    throw
}

# Wait for LIN1 to become SSH-reachable
Write-Host ""
Write-Host "[LIN1] Waiting for SSH reachability (up to 30 min)..." -ForegroundColor Cyan
Write-Host "  Ubuntu autoinstall typically takes 10-15 minutes" -ForegroundColor Gray
Write-Host ""

$lin1Ready = $false
$lin1Deadline = [datetime]::Now.AddMinutes(30)
$startTime = [datetime]::Now

while ([datetime]::Now -lt $lin1Deadline) {
    $lin1Ips = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }
    
    if ($lin1Ips) {
        $lin1DhcpIp = $lin1Ips | Select-Object -First 1
        $sshCheck = Test-NetConnection -ComputerName $lin1DhcpIp -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($sshCheck.TcpTestSucceeded) {
            $lin1Ready = $true
            Write-Host "  [OK] LIN1 is SSH-reachable at $lin1DhcpIp" -ForegroundColor Green
            break
        }
    }
    
    $elapsed = [datetime]::Now - $startTime
    $remaining = $lin1Deadline - [datetime]::Now
    Write-Host "    Still waiting for LIN1 DHCP lease... (elapsed: $($elapsed.TotalMinutes.ToString('F1'))m, remaining: $($remaining.TotalMinutes.ToString('F1'))m)" -ForegroundColor Gray
    Start-Sleep -Seconds 30
}

if (-not $lin1Ready) {
    Write-Host ""
    Write-Host "  [WARN] LIN1 did not become SSH-reachable within 30 minutes" -ForegroundColor Yellow
    Write-Host "  This is normal if autoinstall is still in progress." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    1. Open Hyper-V Manager and connect to LIN1 console" -ForegroundColor White
    Write-Host "    2. Wait for Ubuntu installation to complete (watch for reboot)" -ForegroundColor White
    Write-Host "    3. Run: .\Configure-LIN1.ps1" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Run post-install configuration
Write-Host ""
Write-Host "[LIN1] Running post-install configuration..." -ForegroundColor Cyan

$HostPublicKeyFileName = [System.IO.Path]::GetFileName($SSHPublicKey)
Copy-LabFileItem -Path $SSHPublicKey -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

$linUser = $LabInstallUser
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

try {
    Invoke-BashOnLIN1 -BashScript $script -ActivityName 'Configure-LIN1-PostDeploy' -Variables $vars | Out-Null
    Write-Host "  [OK] Post-install configuration complete" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Post-install configuration failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  You can run .\Configure-LIN1.ps1 manually later" -ForegroundColor Yellow
}

# Finalize boot media so LIN1 does not return to installer on reboot
Write-Host "  Finalizing LIN1 boot media (detach installer + seed disk)..." -ForegroundColor Gray
Finalize-LIN1InstallMedia -VMName 'LIN1' | Out-Null

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " LIN1 Successfully Added to Lab!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  VM Name: LIN1" -ForegroundColor White
Write-Host "  IP Address: $lin1DhcpIp" -ForegroundColor White
Write-Host "  Username: $linUser" -ForegroundColor White
Write-Host "  Password: $AdminPassword" -ForegroundColor White
Write-Host ""
Write-Host "  Test SSH: ssh $linUser@$lin1DhcpIp" -ForegroundColor Cyan
Write-Host ""
