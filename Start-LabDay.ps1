# Start-LabDay.ps1 -- Morning startup for OpenCode Dev Lab
# Starts all VMs, waits for boot, runs health check, shows connection info.

#Requires -RunAsAdministrator

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }


$ErrorActionPreference = 'Stop'

Write-Host "`n=== OPENCODE LAB -- MORNING STARTUP ===" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n" -ForegroundColor Gray

# Import lab
try {
    Import-Lab -Name $LabName -ErrorAction Stop
    Write-Host "  [OK] Lab definition loaded" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Could not import lab. Has it been deployed?" -ForegroundColor Red
    Write-Host "  Run: .\$DeployScript" -ForegroundColor Yellow
    exit 1
}

# Start all VMs
Write-Host "`n  Starting VMs..." -ForegroundColor Yellow
Start-LabVM -All -Wait
Write-Host "  [OK] All VMs started" -ForegroundColor Green

# Health check
Write-Host "`n  Running health check..." -ForegroundColor Yellow
$vms = Get-LabVM
foreach ($vm in $vms) {
    $state = (Get-VM -Name $vm.Name -ErrorAction SilentlyContinue).State
    if ($state -eq 'Running') {
        Write-Host "  [OK] $($vm.Name) -- Running" -ForegroundColor Green
    } else {
        Write-Host "  [!!] $($vm.Name) -- $state" -ForegroundColor Red
    }
}

# Get LIN1 IP for connection info
$lin1IP = $null
$lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
if ($lin1Vm) {
    if (Get-Command Get-LIN1IPv4 -ErrorAction SilentlyContinue) {
        $lin1IP = Get-LIN1IPv4
    } else {
        $lin1Adapter = Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lin1Adapter -and ($lin1Adapter.PSObject.Properties.Name -contains 'IPAddresses')) {
            $lin1IP = @($lin1Adapter.IPAddresses) |
                Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } |
                Select-Object -First 1
        }
    }
}

Write-Host "`n=== LAB READY ===" -ForegroundColor Green
Write-Host "  DC1:   Enter-PSSession -VMName DC1" -ForegroundColor Gray
Write-Host "  WS1:   Enter-PSSession -VMName WS1" -ForegroundColor Gray
if ($lin1IP) {
    Write-Host "  LIN1:  ssh -i $SSHKey $LinuxUser@$lin1IP" -ForegroundColor Gray
} else {
    if ($lin1Vm) {
        Write-Host "  LIN1:  (waiting for IP -- check Lab Status in a minute)" -ForegroundColor Yellow
    } else {
        Write-Host "  LIN1:  (not present in this lab run)" -ForegroundColor DarkGray
    }
}
Write-Host ""
