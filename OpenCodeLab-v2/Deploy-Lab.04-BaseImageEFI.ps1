function Invoke-DeployBaseImageValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMPath
    )

    Write-DeployProgress -Percent 21 -Status 'Creating base images (if needed)...'

    Write-Host ''
    Write-Host 'Creating base disk images...' -ForegroundColor Yellow
    try {
        Install-Lab -BaseImages -ErrorAction Stop
        Write-Host '  Base images ready' -ForegroundColor Green
        Write-DeployEvent -Type 'baseimage.complete' -Status 'ok' -Message 'Base images created'
    }
    catch {
        Write-Host "  Base image creation error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Install-Lab will retry base image creation' -ForegroundColor Yellow
        Write-DeployEvent -Type 'deploy.error' -Status 'error' -Message $_.Exception.Message
    }

    Write-DeployProgress -Percent 25 -Status 'Validating EFI boot partitions on base images...'

    $baseVhdxFiles = Get-ChildItem $VMPath -Filter 'BASE_*.vhdx' -ErrorAction SilentlyContinue
    $efiRepairCount = 0

    foreach ($baseVhdx in $baseVhdxFiles) {
        Write-Host "  Checking: $($baseVhdx.Name) ($([math]::Round($baseVhdx.Length/1GB,1))GB)" -ForegroundColor Gray

        Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
        Start-Sleep 1

        $mounted = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Mount-VHD -Path $baseVhdx.FullName -ErrorAction Stop
                $mounted = $true
                break
            }
            catch {
                Write-Host "    Mount attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
                Start-Sleep -Seconds 3
            }
        }

        if (-not $mounted) {
            Write-Host '    [SKIP] Could not mount - Install-Lab may still work' -ForegroundColor Yellow
            continue
        }

        Start-Sleep 2

        try {
            $disk = Get-VHD -Path $baseVhdx.FullName
            $diskNumber = $disk.DiskNumber
            $partitions = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue

            $efiPart = $partitions | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            $winPart = $partitions | Where-Object { $_.Type -eq 'Basic' -and $_.Size -gt 1GB }

            if (-not $efiPart) {
                Write-Host '    [OK] No EFI partition (MBR/Gen1 disk)' -ForegroundColor Green
                continue
            }

            if (-not $winPart) {
                Write-Host '    [WARN] No Windows partition found' -ForegroundColor Yellow
                continue
            }

            $usedLetters = @(Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
            $efiLetter = $null
            $winLetter = if ($winPart.DriveLetter) { [string]$winPart.DriveLetter } else { $null }

            foreach ($code in 83..90) {
                $l = [string][char]$code
                if ($l -notin $usedLetters -and $l -ne $winLetter) { $efiLetter = $l; break }
            }
            if (-not $winLetter) {
                foreach ($code in 71..82) {
                    $l = [string][char]$code
                    if ($l -notin $usedLetters -and $l -ne $efiLetter) { $winLetter = $l; break }
                }
                if ($winLetter) {
                    Set-Partition -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $winLetter
                }
            }

            if (-not $efiLetter -or -not $winLetter) {
                Write-Host '    [WARN] No available drive letters for EFI check' -ForegroundColor Yellow
                continue
            }

            Set-Partition -DiskNumber $diskNumber -PartitionNumber $efiPart.PartitionNumber -NewDriveLetter $efiLetter
            Start-Sleep 2

            $bcdPath = "${efiLetter}:\EFI\Microsoft\Boot\BCD"
            $bootEfiPath = "${efiLetter}:\EFI\Microsoft\Boot\bootmgfw.efi"

            if ((Test-Path $bcdPath) -and (Test-Path $bootEfiPath)) {
                Write-Host '    [OK] EFI boot files present' -ForegroundColor Green
            }
            else {
                Write-Host '    [FIX] EFI partition missing boot files - running bcdboot...' -ForegroundColor Yellow
                Write-DeployEvent -Type 'efi.repair' -Status 'warning' -Message 'EFI boot repair attempted for base image' -Properties @{ baseImage = $baseVhdx.Name }

                $winDir = "${winLetter}:\Windows"
                if (-not (Test-Path $winDir)) {
                    Write-Host "    [ERROR] Windows directory not found at $winDir" -ForegroundColor Red
                    continue
                }

                $bootEfiSrc = "${winLetter}:\Windows\Boot\EFI"
                Write-Host "    Source boot dir: $bootEfiSrc (exists: $(Test-Path $bootEfiSrc))" -ForegroundColor Gray

                $winPSExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

                $guestBcdboot = "${winLetter}:\Windows\System32\bcdboot.exe"
                $hostBcdboot = "$env:SystemRoot\System32\bcdboot.exe"

                if (Test-Path $guestBcdboot) {
                    Write-Host "    [Method 1] Using VHDX's own bcdboot.exe (Server 2019)..." -ForegroundColor Gray
                    $bcdbootResult = & $winPSExe -NoProfile -Command "& '$guestBcdboot' '${winLetter}:\Windows' /s '${efiLetter}:' /f UEFI 2>&1; Write-Host `\"EXIT:`$LASTEXITCODE`\"; exit `$LASTEXITCODE" 2>&1
                    $bcdbootExit = $LASTEXITCODE
                    Write-Host "    Result (exit $bcdbootExit): $bcdbootResult" -ForegroundColor Gray

                    if ($bcdbootExit -eq 0 -and (Test-Path $bcdPath)) {
                        Write-Host '    [OK] Guest bcdboot succeeded - proper BCD created!' -ForegroundColor Green
                        $efiRepairCount++
                    }
                    else {
                        Write-Host '    [WARN] Guest bcdboot failed, trying host bcdboot...' -ForegroundColor Yellow
                    }
                }

                if (-not (Test-Path $bcdPath)) {
                    Write-Host '    [Method 2] Host bcdboot via cmd.exe...' -ForegroundColor Gray
                    $bcdbootResult2 = & cmd.exe /c "`\"$hostBcdboot`\" `\"${winLetter}:\Windows`\" /s ${efiLetter}: /f UEFI" 2>&1
                    $bcdbootExit2 = $LASTEXITCODE
                    Write-Host "    Result (exit $bcdbootExit2): $bcdbootResult2" -ForegroundColor Gray

                    if ($bcdbootExit2 -eq 0 -and (Test-Path $bcdPath)) {
                        Write-Host '    [OK] Host bcdboot succeeded!' -ForegroundColor Green
                        $efiRepairCount++
                    }
                }

                if (-not (Test-Path $bcdPath)) {
                    Write-Host '    [Method 3] Manual EFI boot file copy + BCD...' -ForegroundColor Yellow

                    $srcBootEfi = "${winLetter}:\Windows\Boot\EFI"
                    if (Test-Path "$srcBootEfi\bootmgfw.efi") {
                        $efiBootDir = "${efiLetter}:\EFI\Microsoft\Boot"
                        New-Item -Path $efiBootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                        New-Item -Path "${efiLetter}:\EFI\Boot" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

                        Copy-Item "$srcBootEfi\bootmgfw.efi" "$efiBootDir\bootmgfw.efi" -Force -ErrorAction SilentlyContinue
                        Copy-Item "$srcBootEfi\bootmgfw.efi" "${efiLetter}:\EFI\Boot\bootx64.efi" -Force -ErrorAction SilentlyContinue
                        if (Test-Path "$srcBootEfi\memtest.efi") {
                            Copy-Item "$srcBootEfi\memtest.efi" "$efiBootDir\memtest.efi" -Force -ErrorAction SilentlyContinue
                        }
                        Get-ChildItem $srcBootEfi -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                            $destDir = "$efiBootDir\$($_.Name)"
                            New-Item -Path $destDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                            Copy-Item "$($_.FullName)\*" $destDir -Force -ErrorAction SilentlyContinue
                        }
                        Copy-Item "$srcBootEfi\boot.stl" "$efiBootDir\boot.stl" -Force -ErrorAction SilentlyContinue
                        Copy-Item "$srcBootEfi\winsipolicy.p7b" "$efiBootDir\winsipolicy.p7b" -Force -ErrorAction SilentlyContinue

                        Write-Host '    Creating BCD store...' -ForegroundColor Gray
                        $bcdStore = "$efiBootDir\BCD"
                        $bcdeditResult = & $winPSExe -NoProfile -Command @"
                        `$s = '$bcdStore'
                        bcdedit /createstore `$s 2>&1
                        bcdedit /store `$s /create '{bootmgr}' /d 'Windows Boot Manager' 2>&1
                        bcdedit /store `$s /set '{bootmgr}' device boot 2>&1
                        bcdedit /store `$s /set '{bootmgr}' path \EFI\Microsoft\Boot\bootmgfw.efi 2>&1
                        `$g = (bcdedit /store `$s /create /d 'Windows Server' /application osloader 2>&1) -replace '.*(\{.*\}).*','`$1'
                        bcdedit /store `$s /set `$g device 'locate=\Windows\system32\winload.efi' 2>&1
                        bcdedit /store `$s /set `$g osdevice 'locate=\Windows\system32\ntoskrnl.exe' 2>&1
                        bcdedit /store `$s /set `$g path \Windows\system32\winload.efi 2>&1
                        bcdedit /store `$s /set `$g systemroot \Windows 2>&1
                        bcdedit /store `$s /set `$g locale en-US 2>&1
                        bcdedit /store `$s /set '{bootmgr}' default `$g 2>&1
                        bcdedit /store `$s /set '{bootmgr}' displayorder `$g 2>&1
                        bcdedit /store `$s /set '{bootmgr}' timeout 0 2>&1
"@ 2>&1
                        Write-Host "    bcdedit: $($bcdeditResult | Out-String)" -ForegroundColor Gray

                        if (Test-Path $bcdPath) {
                            Write-Host '    [OK] Manual boot file copy + BCD succeeded!' -ForegroundColor Green
                            $efiRepairCount++
                        }
                        else {
                            Write-Host '    [FAIL] BCD creation failed' -ForegroundColor Red
                        }
                    }
                    else {
                        Write-Host '    [FAIL] No bootmgfw.efi found in VHDX' -ForegroundColor Red
                    }
                }
            }

            Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $efiPart.PartitionNumber -AccessPath "${efiLetter}:\" -ErrorAction SilentlyContinue
            if (-not $winPart.DriveLetter) {
                Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -AccessPath "${winLetter}:\" -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Host "    [ERROR] EFI check failed: $_" -ForegroundColor Red
        }
        finally {
            Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
        }
    }

    if ($efiRepairCount -gt 0) {
        Write-Host ''
        Write-Host "  Repaired EFI boot files on $efiRepairCount base image(s)" -ForegroundColor Green
    }

    Write-DeployProgress -Percent 30 -Status 'Base image EFI validation complete'
}
