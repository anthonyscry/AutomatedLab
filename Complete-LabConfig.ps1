# Complete-LabConfig.ps1
# Run this after manually installing Windows on all VMs
# Configures network, promotes DC, joins domain, and creates checkpoint

Write-Host "=== Completing Lab Configuration ===" -ForegroundColor Cyan
Write-Host ""

# Verify VMs are running
Write-Host "Checking VM status..." -ForegroundColor Yellow
$runningVMs = Get-VM | Where-Object { $_.Name -like "Simple*" -and $_.State -eq "Running" }

if ($runningVMs.Count -lt 3) {
    Write-Host "ERROR: Not all VMs are running. Please start all VMs first." -ForegroundColor Red
    exit 1
}

Write-Host "All VMs are running." -ForegroundColor Green
Write-Host ""

# Configure network
Write-Host "Configuring network..." -ForegroundColor Yellow
Initialize-LabNetwork

Write-Host "`nNOTE: If network configuration failed, make sure:" -ForegroundColor Yellow
Write-Host "  1. Windows is fully installed on each VM" -ForegroundColor Yellow
Write-Host "  2. VMs are running" -ForegroundColor Yellow
Write-Host "  3. You can manually connect to VMs via Hyper-V Manager" -ForegroundColor Yellow
Write-Host ""
