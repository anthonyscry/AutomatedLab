function Start-LabVMs {
    <#
    .SYNOPSIS
        Starts all SimpleLab virtual machines.

    .DESCRIPTION
        Starts all configured lab VMs in the correct order (DC first, then servers, then clients).
        Optionally waits for VMs to be fully started and reports status.

    .PARAMETER SwitchName
        Name of the virtual switch (default: "SimpleLab").

    .PARAMETER Wait
        Wait for VMs to fully start before returning.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for VM startup (default: 300).

    .OUTPUTS
        PSCustomObject with startup results including VMsStarted, FailedVMs, OverallStatus, Message, and Duration.

    .EXAMPLE
        Start-LabVMs

    .EXAMPLE
        Start-LabVMs -Wait -TimeoutSeconds 600
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SwitchName = "SimpleLab",

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds = 300
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsStarted = @()
        FailedVMs = @()
        AlreadyRunning = @()
        OverallStatus = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.OverallStatus = "Failed"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 2: Get VM configurations
        $vmConfigs = Get-LabVMConfig
        if ($null -eq $vmConfigs) {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to retrieve VM configurations"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 3: Start order: DC first, then other servers, then clients
        $startOrder = @("dc1", "svr1", "ws1")

        # Start DC first (synchronous)
        $dcName = $startOrder | Where-Object { $_ -eq 'dc1' } | Select-Object -First 1
        if ($dcName) {
            $vm = Get-VM -Name $dcName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$dcName' does not exist, skipping"
            }
            elseif ($vm.State -eq "Running") {
                Write-Verbose "VM '$dcName' is already running"
                $result.AlreadyRunning += $dcName
            }
            else {
                try {
                    Write-Verbose "Starting VM '$dcName'..."
                    Start-VM -Name $dcName -ErrorAction Stop
                    $result.VMsStarted += $dcName
                    Write-Verbose "VM '$dcName' start command sent"
                }
                catch {
                    Write-Error "Failed to start VM '$dcName': $($_.Exception.Message)"
                    $result.FailedVMs += $dcName
                }
            }
        }

        # Start remaining VMs in parallel
        $otherVMs = $startOrder | Where-Object { $_ -ne 'dc1' }
        $jobs = @()

        foreach ($vmName in $otherVMs) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                continue
            }

            if ($vm.State -eq "Running") {
                Write-Verbose "VM '$vmName' is already running"
                $result.AlreadyRunning += $vmName
                continue
            }

            $jobs += Start-Job -ScriptBlock {
                param($Name)
                try {
                    Import-Module Hyper-V -ErrorAction Stop
                    Start-VM -Name $Name -ErrorAction Stop | Out-Null
                    [pscustomobject]@{ VMName = $Name; Success = $true; ErrorMessage = '' }
                }
                catch {
                    [pscustomobject]@{ VMName = $Name; Success = $false; ErrorMessage = $_.Exception.Message }
                }
            } -ArgumentList $vmName
        }

        if ($jobs.Count -gt 0) {
            $jobs | Wait-Job -Timeout $TimeoutSeconds | Out-Null

            foreach ($job in $jobs) {
                $jobOutput = @()
                if ($job.State -eq 'Completed') {
                    $jobOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
                }

                if ($job.State -eq 'Completed' -and $jobOutput.Count -gt 0 -and $jobOutput[0].Success) {
                    $result.VMsStarted += $jobOutput[0].VMName
                    Write-Verbose "VM '$($jobOutput[0].VMName)' start command sent"
                }
                elseif ($job.State -eq 'Completed' -and $jobOutput.Count -gt 0) {
                    Write-Error "Failed to start VM '$($jobOutput[0].VMName)': $($jobOutput[0].ErrorMessage)"
                    $result.FailedVMs += $jobOutput[0].VMName
                }
                else {
                    if ($job.State -eq 'Running') {
                        Stop-Job -Job $job -ErrorAction SilentlyContinue
                    }
                    $failedName = if ($jobOutput.Count -gt 0 -and $jobOutput[0].VMName) { $jobOutput[0].VMName } else { "Job-$($job.Id)" }
                    Write-Error "Failed to start VM '$failedName': Job did not complete successfully"
                    $result.FailedVMs += $failedName
                }

                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }

        # Step 4: Wait for VMs to be ready if requested
        if ($Wait -and $result.VMsStarted.Count -gt 0) {
            $waitStart = Get-Date
            foreach ($vmName in $result.VMsStarted) {
                $elapsed = 0
                while ($elapsed -lt $TimeoutSeconds) {
                    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
                    if ($vm -and $vm.State -eq "Running" -and $vm.Heartbeat -eq "Ok") {
                        Write-Verbose "VM '$vmName' is fully started and responsive"
                        break
                    }
                    Start-Sleep -Seconds 5
                    $elapsed = (New-TimeSpan -Start $waitStart -End (Get-Date)).TotalSeconds
                }

                if ($elapsed -ge $TimeoutSeconds) {
                    Write-Warning "VM '$vmName' did not reach ready state within timeout"
                }
            }
        }

        # Step 5: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        $totalVMs = $result.VMsStarted.Count + $result.FailedVMs.Count + $result.AlreadyRunning.Count
        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Started $($result.VMsStarted.Count) VM(s), $($result.AlreadyRunning.Count) already running"
        }
        elseif ($result.VMsStarted.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Started $($result.VMsStarted.Count) VM(s), failed $($result.FailedVMs.Count), $($result.AlreadyRunning.Count) already running"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to start any VMs"
        }

        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
