# Start-LabDay.ps1 -- Morning startup for OpenCode Dev Lab
# Starts all VMs, waits for boot, runs health check, shows connection info.

#Requires -RunAsAdministrator

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $RepoRoot 'Lab-Config.ps1'
$CommonPath = Join-Path $RepoRoot 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }


$ErrorActionPreference = 'Stop'

Write-Host "`n=== OPENCODE LAB -- MORNING STARTUP ===" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n" -ForegroundColor Gray

# Import lab
try {
    Import-Lab -Name $GlobalLabConfig.Lab.Name -ErrorAction Stop
    Write-LabStatus -Status OK -Message "Lab definition loaded"
} catch {
    Write-LabStatus -Status FAIL -Message "Could not import lab. Has it been deployed?"
    Write-Host "  Run: .\$DeployScript" -ForegroundColor Yellow
    exit 1
}

# Start all VMs
Write-Host "`n  Starting VMs..." -ForegroundColor Yellow
$missingVMs = @()
$definedVMs = @(Get-LabVM)
foreach ($vm in $definedVMs) {
    if (-not (Get-VM -Name $vm.Name -ErrorAction SilentlyContinue)) {
        $missingVMs += $vm.Name
    }
}

if ($missingVMs.Count -gt 0) {
    Write-LabStatus -Status FAIL -Message "Hyper-V VM(s) missing: $($missingVMs -join ', ')"
    Write-Host "  Lab definition exists but VM instances are not present on this host." -ForegroundColor Yellow
    Write-Host "  Recreate them with: .\Deploy.ps1 -NonInteractive" -ForegroundColor Yellow
    exit 1
}

Start-LabVM -All -Wait
Write-LabStatus -Status OK -Message "All VMs started"

# Health check
Write-Host "`n  Running health check..." -ForegroundColor Yellow
$vms = Get-LabVM
foreach ($vm in $vms) {
    $state = (Get-VM -Name $vm.Name -ErrorAction SilentlyContinue).State
    if ($state -eq 'Running') {
        Write-LabStatus -Status OK -Message "$($vm.Name) -- Running"
    } else {
        Write-Host "  [!!] $($vm.Name) -- $state" -ForegroundColor Red
    }
}

# Get LIN1 IP for connection info
$lin1IP = $null
$lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
if ($lin1Vm) {
    if (Get-Command Get-LinuxVMIPv4 -ErrorAction SilentlyContinue) {
        $lin1IP = Get-LinuxVMIPv4 -VMName 'LIN1'
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
Write-Host "  SVR1:  Enter-PSSession -VMName SVR1" -ForegroundColor Gray
Write-Host "  WS1:   Enter-PSSession -VMName WS1" -ForegroundColor Gray
if ($lin1IP) {
    Write-Host "  LIN1:  ssh -i $SSHKey $GlobalLabConfig.Credentials.LinuxUser@$lin1IP" -ForegroundColor Gray
} else {
    if ($lin1Vm) {
        Write-Host "  LIN1:  (waiting for IP -- check Lab Status in a minute)" -ForegroundColor Yellow
    } else {
        Write-Host "  LIN1:  (not present in this lab run)" -ForegroundColor DarkGray
    }
}
Write-Host ""
