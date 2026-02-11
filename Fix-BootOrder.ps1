# Fix-BootOrder.ps1 - Sets DVD as first boot device for existing SimpleLab VMs
# Run this to fix VMs that are stuck at UEFI screen

$vmNames = @("dc1", "svr1", "ws1")

Write-Host "Configuring boot order for SimpleLab VMs..." -ForegroundColor Cyan

foreach ($vmName in $vmNames) {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue

    if ($null -eq $vm) {
        Write-Host "  [SKIP] VM '$vmName' not found" -ForegroundColor Yellow
        continue
    }

    if ($vm.State -ne "Off") {
        Write-Host "  [STOP] Stopping '$vmName'..." -ForegroundColor Yellow
        Stop-VM -Name $vmName -Force
        Start-Sleep -Seconds 2
    }

    $dvdDrive = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue

    if ($null -eq $dvdDrive) {
        Write-Host "  [SKIP] '$vmName' has no DVD drive" -ForegroundColor Yellow
        continue
    }

    Set-VMFirmware -VMName $vmName -FirstBootDevice $dvdDrive -ErrorAction Stop
    Write-Host "  [OK] '$vmName' - DVD set as first boot device" -ForegroundColor Green
}

Write-Host "`nBoot order configured! You can now start the VMs:" -ForegroundColor Green
Write-Host "  .\SimpleLab.ps1" -ForegroundColor White
