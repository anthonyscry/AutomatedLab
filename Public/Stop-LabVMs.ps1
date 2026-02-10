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
        $stopOrder = @("SimpleWin11", "SimpleServer", "SimpleDC")

        foreach ($vmName in $stopOrder) {
            # Check if VM exists
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                continue
            }

            # Check current state
            if ($vm.State -eq "Off") {
                Write-Verbose "VM '$vmName' is already stopped"
                $result.AlreadyStopped += $vmName
                continue
            }

            # Stop the VM
            try {
                if ($Force) {
                    Write-Verbose "Turning off VM '$vmName'..."
                    Stop-VM -Name $vmName -TurnOff -Force -ErrorAction Stop
                }
                else {
                    Write-Verbose "Shutting down VM '$vmName'..."
                    Stop-VM -Name $vmName -Force -ErrorAction Stop
                }
                $result.VMsStopped += $vmName
                Write-Verbose "VM '$vmName' stop command sent"
            }
            catch {
                Write-Error "Failed to stop VM '$vmName': $($_.Exception.Message)"
                $result.FailedVMs += $vmName
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
