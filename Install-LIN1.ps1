# Install-LIN1.ps1 - Create LIN1 after core lab deploy, then run LIN1 SSH/bootstrap config
# Intended flow: build core lab first (DC1 + WS1), then run this script as one-click LIN1 add-on.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$AdminPassword = 'Server123!'
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
    $AdminPassword = 'Server123!'
    Write-Host "  [WARN] AdminPassword was empty. Falling back to default password." -ForegroundColor Yellow
}

if (-not (Import-OpenCodeLab -Name $LabName)) {
    throw "Lab '$LabName' is not imported. Build core lab first with one-button-setup/deploy."
}

$ubuntuIso = Join-Path $LabSourcesRoot 'ISOs\ubuntu-24.04.3.iso'
if (-not (Test-Path $ubuntuIso)) {
    throw "Ubuntu ISO not found: $ubuntuIso"
}

$lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
if (-not $lin1Vm) {
    Write-Host "[LIN1] Creating LIN1 VM (post-deploy add-on)..." -ForegroundColor Cyan

    $null = New-VM -Name 'LIN1' -Generation 2 -MemoryStartupBytes $UBU_Memory -SwitchName $LabSwitch -Path $LabPath
    Set-VMMemory -VMName 'LIN1' -DynamicMemoryEnabled $true -StartupBytes $UBU_Memory -MinimumBytes $UBU_MinMemory -MaximumBytes $UBU_MaxMemory
    Set-VMProcessor -VMName 'LIN1' -Count $UBU_Processors
    Set-VM -Name 'LIN1' -AutomaticCheckpointsEnabled $false

    Add-VMDvdDrive -VMName 'LIN1' -Path $ubuntuIso | Out-Null
    $dvd = Get-VMDvdDrive -VMName 'LIN1'
    Set-VMFirmware -VMName 'LIN1' -EnableSecureBoot Off -FirstBootDevice $dvd

    Write-Host "  [OK] LIN1 VM created and boot configured from Ubuntu ISO." -ForegroundColor Green
    $lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
} else {
    Write-Host "[LIN1] VM already exists. Reusing existing LIN1." -ForegroundColor Yellow
}

if ($lin1Vm.State -ne 'Running') {
    Start-VM -Name 'LIN1' | Out-Null
}

Write-Host "[LIN1] Waiting for SSH reachability (up to 45 min)..." -ForegroundColor Cyan
$lin1Ready = $false
$deadline = [datetime]::Now.AddMinutes(45)
while ([datetime]::Now -lt $deadline) {
    $lin1Ips = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }
    if ($lin1Ips) {
        $ip = $lin1Ips | Select-Object -First 1
        $ssh = Test-NetConnection -ComputerName $ip -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($ssh.TcpTestSucceeded) {
            $lin1Ready = $true
            Write-Host "  [OK] LIN1 SSH reachable at $ip" -ForegroundColor Green
            break
        }
    }
    Start-Sleep -Seconds 30
}

if (-not $lin1Ready) {
    throw "LIN1 did not become SSH reachable. Complete Ubuntu install in VM console and re-run Install-LIN1.ps1 or lin1-config."
}

$configureScript = Join-Path $ScriptDir 'Configure-LIN1.ps1'
if (-not (Test-Path $configureScript)) {
    throw "Configure-LIN1.ps1 not found at $configureScript"
}

Write-Host "[LIN1] Running post-deploy LIN1 SSH/bootstrap config..." -ForegroundColor Cyan
& $configureScript -NonInteractive -AdminPassword $AdminPassword
Write-Host "[OK] LIN1 install/config flow complete." -ForegroundColor Green
