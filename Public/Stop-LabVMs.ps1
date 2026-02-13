function Stop-LabVMs {
    <#
    .SYNOPSIS
        Stops all SimpleLab virtual machines.

    .DESCRIPTION
        Stops all running lab VMs. Can shut down gracefully or force turn off.
        Stops VMs in reverse dependency order (clients first, then servers, then DC).

    .PARAMETER SwitchName
        Name of the virtual switch (default: "SimpleLab").

    .PARAMETER Force
        Force turn off VMs instead of graceful shutdown.

    .PARAMETER Wait
        Wait for VMs to fully stop before returning.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for VM shutdown (default: 60).

    .OUTPUTS
        PSCustomObject with stop results including VMsStopped, FailedVMs, OverallStatus, Message, and Duration.

    .EXAMPLE
        Stop-LabVMs

    .EXAMPLE
        Stop-LabVMs -Force
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SwitchName = "SimpleLab",

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds = 60
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsStopped = @()
        FailedVMs = @()
        AlreadyStopped = @()
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

        # Step 3: Stop order: reverse of start (clients first, then DC)
        $stopOrder = @("ws1", "svr1", "dc1")

        # Stop clients + member servers in parallel first
        $nonDcVMs = $stopOrder | Where-Object { $_ -ne 'dc1' }
        $jobs = @()

        foreach ($vmName in $nonDcVMs) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                continue
            }

            if ($vm.State -eq "Off") {
                Write-Verbose "VM '$vmName' is already stopped"
                $result.AlreadyStopped += $vmName
                continue
            }

            $jobs += Start-Job -ScriptBlock {
                param($Name, $UseForce)
                try {
                    Import-Module Hyper-V -ErrorAction Stop
                    if ($UseForce) {
                        Stop-VM -Name $Name -TurnOff -Force -ErrorAction Stop | Out-Null
                    }
                    else {
                        Stop-VM -Name $Name -Force -ErrorAction Stop | Out-Null
                    }
                    [pscustomobject]@{ VMName = $Name; Success = $true; ErrorMessage = '' }
                }
                catch {
                    [pscustomobject]@{ VMName = $Name; Success = $false; ErrorMessage = $_.Exception.Message }
                }
            } -ArgumentList $vmName, [bool]$Force
        }

        if ($jobs.Count -gt 0) {
            $jobs | Wait-Job -Timeout $TimeoutSeconds | Out-Null

            foreach ($job in $jobs) {
                $jobOutput = @()
                if ($job.State -eq 'Completed') {
                    $jobOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
                }

                if ($job.State -eq 'Completed' -and $jobOutput.Count -gt 0 -and $jobOutput[0].Success) {
                    if ($Force) {
                        Write-Verbose "Turning off VM '$($jobOutput[0].VMName)'..."
                    }
                    else {
                        Write-Verbose "Shutting down VM '$($jobOutput[0].VMName)'..."
                    }
                    $result.VMsStopped += $jobOutput[0].VMName
                    Write-Verbose "VM '$($jobOutput[0].VMName)' stop command sent"
                }
                elseif ($job.State -eq 'Completed' -and $jobOutput.Count -gt 0) {
                    Write-Error "Failed to stop VM '$($jobOutput[0].VMName)': $($jobOutput[0].ErrorMessage)"
                    $result.FailedVMs += $jobOutput[0].VMName
                }
                else {
                    if ($job.State -eq 'Running') {
                        Stop-Job -Job $job -ErrorAction SilentlyContinue
                    }
                    $failedName = if ($jobOutput.Count -gt 0 -and $jobOutput[0].VMName) { $jobOutput[0].VMName } else { "Job-$($job.Id)" }
                    Write-Error "Failed to stop VM '$failedName': Job did not complete successfully"
                    $result.FailedVMs += $failedName
                }

                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }

        # Stop DC last
        $dcVmName = $stopOrder | Where-Object { $_ -eq 'dc1' } | Select-Object -First 1
        if ($dcVmName) {
            $vm = Get-VM -Name $dcVmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$dcVmName' does not exist, skipping"
            }
            elseif ($vm.State -eq "Off") {
                Write-Verbose "VM '$dcVmName' is already stopped"
                $result.AlreadyStopped += $dcVmName
            }
            else {
                try {
                    if ($Force) {
                        Write-Verbose "Turning off VM '$dcVmName'..."
                        Stop-VM -Name $dcVmName -TurnOff -Force -ErrorAction Stop
                    }
                    else {
                        Write-Verbose "Shutting down VM '$dcVmName'..."
                        Stop-VM -Name $dcVmName -Force -ErrorAction Stop
                    }
                    $result.VMsStopped += $dcVmName
                    Write-Verbose "VM '$dcVmName' stop command sent"
                }
                catch {
                    Write-Error "Failed to stop VM '$dcVmName': $($_.Exception.Message)"
                    $result.FailedVMs += $dcVmName
                }
            }
        }

        # Step 4: Wait for VMs to fully stop if requested
        if ($Wait -and $result.VMsStopped.Count -gt 0) {
            $waitStart = Get-Date
            foreach ($vmName in $result.VMsStopped) {
                $elapsed = 0
                while ($elapsed -lt $TimeoutSeconds) {
                    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
                    if ($vm -and $vm.State -eq "Off") {
                        Write-Verbose "VM '$vmName' is fully stopped"
                        break
                    }
                    Start-Sleep -Seconds 2
                    $elapsed = (New-TimeSpan -Start $waitStart -End (Get-Date)).TotalSeconds
                }

                if ($elapsed -ge $TimeoutSeconds) {
                    Write-Warning "VM '$vmName' did not stop within timeout"
                }
            }
        }

        # Step 5: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Stopped $($result.VMsStopped.Count) VM(s), $($result.AlreadyStopped.Count) already stopped"
        }
        elseif ($result.VMsStopped.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Stopped $($result.VMsStopped.Count) VM(s), failed $($result.FailedVMs.Count), $($result.AlreadyStopped.Count) already stopped"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to stop any VMs"
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
