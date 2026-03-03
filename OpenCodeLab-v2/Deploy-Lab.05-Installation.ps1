function Invoke-DeployInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabName,
        [Parameter(Mandatory = $false)]
        [string]$AdminPassword,
        [Parameter(Mandatory = $false)]
        [string]$DomainName,
        [Parameter(Mandatory = $true)]
        [string]$VMPath,
        [Parameter(Mandatory = $true)]
        [array]$VMs
    )

    Write-DeployProgress -Percent 30 -Status 'Installing lab (this takes 15-45 minutes)...'

    Write-Host ''
    Write-Host 'Installing lab (this will take a while)...' -ForegroundColor Yellow
    Write-Host '  - Create VMs, install OS, configure AD, join domain' -ForegroundColor Gray
    Write-Host "  Started at: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
    Write-Host ''

    $installStart = Get-Date
    $installError = $null

    try {
        Install-Lab -ErrorAction Stop
    }
    catch {
        $installError = $_
        Write-Host ''
        Write-Host "  INSTALL-LAB ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Will verify VM creation and attempt recovery...' -ForegroundColor Yellow
        Write-DeployEvent -Type 'deploy.error' -Status 'error' -Message $_.Exception.Message
    }

    $routerVMs = @($VMs | Where-Object { $_.Role -in @('Router', 'Firewall') })
    if ($routerVMs.Count -gt 0) {
        Write-Host "Enabling routing on $($routerVMs.Count) router/firewall VM(s)..." -ForegroundColor Yellow
        foreach ($rvm in $routerVMs) {
            try {
                Enable-LabInternalRouting -RoutingNetworkName $LabName
                Write-Host "  [ROUTING][OK] $($rvm.Name)" -ForegroundColor Green
            }
            catch {
                Write-Warning "  [ROUTING][FAIL] $($rvm.Name): $($_.Exception.Message)"
            }
        }
    }

    $installElapsed = (Get-Date) - $installStart
    Write-Host ('  Install-Lab completed in {0:D2}m {1:D2}s' -f [int]$installElapsed.TotalMinutes, $installElapsed.Seconds) -ForegroundColor Green
    Write-DeployEvent -Type 'install.complete' -Status 'ok' -Message 'Install-Lab completed' -Properties @{ elapsedMinutes = [math]::Round($installElapsed.TotalMinutes, 1) }

    Write-DeployProgress -Percent 78 -Status "Install-Lab finished in $([int]$installElapsed.TotalMinutes)m $($installElapsed.Seconds)s"

    $dcVM = $VMs | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1
    if ($dcVM -and -not $installError) {
        Write-DeployProgress -Percent 78 -Status 'Creating dod_admin domain admin account...'
        try {
            $dcName = $dcVM.Name
            Write-Host "  Creating domain admin account: dod_admin on $dcName" -ForegroundColor Yellow
            Invoke-LabCommand -ComputerName $dcName -ActivityName 'Create dod_admin' -ScriptBlock {
                param($pw)
                Import-Module ActiveDirectory -ErrorAction Stop
                if (-not (Get-ADUser -Filter "SamAccountName -eq 'dod_admin'" -ErrorAction SilentlyContinue)) {
                    if ([string]::IsNullOrWhiteSpace($pw)) {
                        throw 'Admin password cannot be empty when creating dod_admin.'
                    }

                    $secPw = New-Object System.Security.SecureString
                    foreach ($ch in $pw.ToCharArray()) {
                        $secPw.AppendChar($ch)
                    }
                    $secPw.MakeReadOnly()

                    New-ADUser -Name 'dod_admin' -SamAccountName 'dod_admin' -UserPrincipalName "dod_admin@$((Get-ADDomain).DNSRoot)" `
                        -AccountPassword $secPw -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $false `
                        -Description 'Lab Domain Administrator'
                    Add-ADGroupMember -Identity 'Domain Admins' -Members 'dod_admin'
                    Add-ADGroupMember -Identity 'Enterprise Admins' -Members 'dod_admin'
                    Write-Host '  [OK] dod_admin created and added to Domain Admins + Enterprise Admins' -ForegroundColor Green
                }
                else {
                    Write-Host '  [OK] dod_admin already exists' -ForegroundColor Green
                }
            } -ArgumentList $AdminPassword -ErrorAction Stop
            Write-Host '  [OK] dod_admin account ready (password same as admin)' -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] Could not create dod_admin: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-DeployProgress -Percent 79 -Status 'Verifying boot configuration...'

    $needsBootRepair = $false
    foreach ($vm in $VMs) {
        $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
        if (-not $hvVM) { continue }
        if ($hvVM.Generation -eq 2 -and $hvVM.State -eq 'Running') {
            $hb = $hvVM.Heartbeat
            if ($hb -eq 'OkApplicationsHealthy' -or $hb -eq 'OkApplicationsUnknown') {
                Write-Host "  [OK] $($vm.Name) booted with heartbeat: $hb" -ForegroundColor Green
            }
            else {
                Write-Host "  [WARN] $($vm.Name) heartbeat: $hb - may need boot repair" -ForegroundColor Yellow
                $needsBootRepair = $true
            }
        }
    }

    if ($needsBootRepair) {
        Write-Host '  Some VMs may not have booted. Attempting post-install EFI repair...' -ForegroundColor Yellow

        foreach ($vm in $VMs) {
            $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
            if ($hvVM -and $hvVM.State -ne 'Off') {
                Stop-VM -Name $vm.Name -TurnOff -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep 5

        $baseVhdxFiles = Get-ChildItem $VMPath -Filter 'BASE_*.vhdx' -ErrorAction SilentlyContinue
        foreach ($baseVhdx in $baseVhdxFiles) {
            Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
            Start-Sleep 1
            try {
                Mount-VHD -Path $baseVhdx.FullName -ErrorAction Stop
                Start-Sleep 2

                $disk = Get-VHD -Path $baseVhdx.FullName
                $dn = $disk.DiskNumber
                $efiPart = Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue |
                    Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
                $winPart = Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue |
                    Where-Object { $_.Type -eq 'Basic' -and $_.Size -gt 1GB }

                if ($efiPart -and $winPart) {
                    $usedLetters = @(Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
                    $efiL = $null
                    $winL = if ($winPart.DriveLetter) { [string]$winPart.DriveLetter } else { $null }
                    foreach ($c in 83..90) { $l = [string][char]$c; if ($l -notin $usedLetters -and $l -ne $winL) { $efiL = $l; break } }
                    if (-not $winL) {
                        foreach ($c in 71..82) { $l = [string][char]$c; if ($l -notin $usedLetters -and $l -ne $efiL) { $winL = $l; break } }
                        if ($winL) { Set-Partition -DiskNumber $dn -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $winL }
                    }
                    if ($efiL -and $winL) {
                        Set-Partition -DiskNumber $dn -PartitionNumber $efiPart.PartitionNumber -NewDriveLetter $efiL
                        Start-Sleep 2
                        if (-not (Test-Path "${efiL}:\EFI\Microsoft\Boot\BCD")) {
                            Write-Host "  [FIX] Running bcdboot on $($baseVhdx.Name)..." -ForegroundColor Yellow
                            $bcdExe = "$env:SystemRoot\System32\bcdboot.exe"
                            if (-not (Test-Path $bcdExe)) { $bcdExe = 'bcdboot.exe' }
                            & cmd.exe /c "`\"$bcdExe`\" `\"${winL}:\Windows`\" /s ${efiL}: /f UEFI" 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
                        }
                        Remove-PartitionAccessPath -DiskNumber $dn -PartitionNumber $efiPart.PartitionNumber -AccessPath "${efiL}:\" -ErrorAction SilentlyContinue
                    }
                }
            }
            catch {
                Write-Host "  [ERROR] Post-install repair failed: $_" -ForegroundColor Red
            }
            finally {
                Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
            }
        }

        foreach ($vm in $VMs) {
            $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
            if ($hvVM -and $hvVM.State -eq 'Off') {
                Start-VM -Name $vm.Name -ErrorAction SilentlyContinue
                Write-Host "  Restarted $($vm.Name)" -ForegroundColor Green
            }
        }
        Write-Host '  Waiting 60s for VMs to boot...' -ForegroundColor Yellow
        Start-Sleep 60
    }

    Write-DeployProgress -Percent 80 -Status 'Boot verification complete'
    Write-DeployEvent -Type 'postinstall.complete' -Status 'ok' -Message 'Post-install configuration complete'

    foreach ($vm in $VMs) {
        $vmName = $vm.Name
        $hvVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if (-not $hvVM -or $hvVM.Generation -ne 2) { continue }

        $hdd = Get-VMHardDiskDrive -VMName $vmName -ErrorAction SilentlyContinue
        $fw = Get-VMFirmware -VMName $vmName -ErrorAction SilentlyContinue

        if ($hdd -and $fw) {
            $hasHddBoot = $fw.BootOrder | Where-Object { $_.BootType -eq 'Drive' -and $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] }
            if (-not $hasHddBoot) {
                Write-Host "  [FIX] Adding hard drive to boot order for $vmName" -ForegroundColor Yellow
                try { Set-VMFirmware -VMName $vmName -FirstBootDevice $hdd } catch { }
            }
        }
    }

    return @{
        InstallError = $installError
        Elapsed      = $installElapsed
    }
}
