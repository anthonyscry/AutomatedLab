# Wait-LabVMReady.ps1
# Waits for VMs to complete Windows installation and be ready for configuration

function Wait-LabVMReady {
    <#
    .SYNOPSIS
        Waits for VMs to complete Windows installation and be ready for configuration.

    .DESCRIPTION
        Waits for each VM to complete Windows installation and become accessible via
        PowerShell Direct. Uses timeout and retry logic with progress display.

    .PARAMETER VMNames
        Array of VM names to wait for.

    .PARAMETER TimeoutMinutes
        Maximum minutes to wait per VM (default: 75, increase for slower systems).

    .PARAMETER SleepIntervalSeconds
        Maximum seconds between checks (default: 30). The function starts with
        shorter checks and backs off up to this value.

    .OUTPUTS
        PSCustomObject with ReadyVMs, NotReadyVMs, OverallStatus, Duration, Message.

    .EXAMPLE
        Wait-LabVMReady -VMNames @("dc1", "svr1", "ws1")
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$VMNames = @("dc1", "svr1", "ws1"),

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutMinutes = 75,  # 75 min is sufficient for SSD, fast CPU

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SleepIntervalSeconds = 30
    )

    # Start timing
    $startTime = Get-Date
    $timeout = [TimeSpan]::FromMinutes($TimeoutMinutes)

    # Initialize result object
    $result = [PSCustomObject]@{
        ReadyVMs = @()
        NotReadyVMs = @()
        OverallStatus = "Failed"
        Duration = $null
        Message = ""
        VMStatus = @{}
    }

    Write-Host "Waiting for VMs to complete Windows installation..." -ForegroundColor Cyan
    Write-Host "This may take 30-60 minutes. Please be patient." -ForegroundColor Yellow
    Write-Host ""

    $initialSleepSeconds = [Math]::Min($SleepIntervalSeconds, 5)

    foreach ($vmName in $VMNames) {
        $vmStartTime = Get-Date
        $isReady = $false
        $attempt = 0
        $nextSleepSeconds = $initialSleepSeconds

        Write-Host "Waiting for '$vmName'..." -ForegroundColor Yellow

        while (-not $isReady) {
            $attempt++
            $elapsed = New-TimeSpan -Start $vmStartTime -End (Get-Date)

            # Check timeout
            if ($elapsed -gt $timeout) {
                Write-Host "  [TIMEOUT] '$vmName' did not become ready within $TimeoutMinutes minutes" -ForegroundColor Red
                $result.NotReadyVMs += $vmName
                $result.VMStatus[$vmName] = "Timeout"
                break
            }

            # Check if VM is running
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm -or $vm.State -ne "Running") {
                Start-Sleep -Seconds $nextSleepSeconds
                $nextSleepSeconds = [Math]::Min([int]([Math]::Ceiling($nextSleepSeconds * 1.5)), $SleepIntervalSeconds)
                continue
            }

            # Skip expensive guest remoting until heartbeat indicates the guest is responsive.
            $heartbeatReady = @('Ok', 'OperatingNormally') -contains ([string]$vm.Heartbeat)
            if (-not $heartbeatReady) {
                $elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 1)
                Write-Host "  [$($attempt)] VM running, guest not ready yet (${elapsedMinutes}min elapsed)`r" -NoNewline -ForegroundColor Gray
                Start-Sleep -Seconds $nextSleepSeconds
                $nextSleepSeconds = [Math]::Min([int]([Math]::Ceiling($nextSleepSeconds * 1.5)), $SleepIntervalSeconds)
                continue
            }

            # Try to connect via PowerShell Direct
            try {
                $testResult = Invoke-Command -VMName $vmName -ScriptBlock {
                    # Check if Windows is ready by testing if we can run commands
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem
                    return @{
                        Ready = $true
                        OSName = $os.Caption
                        LastBootUpTime = $os.LastBootUpTime
                    }
                } -ErrorAction SilentlyContinue

                if ($null -ne $testResult -and $testResult.Ready) {
                    $isReady = $true
                    $elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 1)
                    Write-Host "  [READY] '$vmName' is ready! (${elapsedMinutes} min) - $($testResult.OSName)" -ForegroundColor Green
                    $result.ReadyVMs += $vmName
                    $result.VMStatus[$vmName] = "Ready"
                    break
                }
            }
            catch {
                Write-Verbose "PowerShell Direct check for '$vmName' not ready yet: $($_.Exception.Message)"
            }

            # Show progress
            $elapsedMinutes = [math]::Round($elapsed.TotalMinutes, 1)
            Write-Host "  [$($attempt)] Waiting... (${elapsedMinutes}min elapsed, next check ${nextSleepSeconds}s)`r" -NoNewline -ForegroundColor Gray

            Start-Sleep -Seconds $nextSleepSeconds
            $nextSleepSeconds = [Math]::Min([int]([Math]::Ceiling($nextSleepSeconds * 1.5)), $SleepIntervalSeconds)
        }

        Write-Host ""  # New line after progress
    }

    # Calculate duration
    $result.Duration = New-TimeSpan -Start $startTime -End (Get-Date)

    # Determine overall status
    if ($result.NotReadyVMs.Count -eq 0) {
        $result.OverallStatus = "OK"
        $result.Message = "All $($result.ReadyVMs.Count) VM(s) are ready"
    }
    elseif ($result.ReadyVMs.Count -eq 0) {
        $result.OverallStatus = "Failed"
        $result.Message = "No VMs became ready"
    }
    else {
        $result.OverallStatus = "Partial"
        $result.Message = "$($result.ReadyVMs.Count) VM(s) ready, $($result.NotReadyVMs.Count) not ready"
    }

    return $result
}
