function Suspend-LabVMs {
    <#
    .SYNOPSIS
        Suspends all running SimpleLab virtual machines.

    .DESCRIPTION
        Suspends all running lab VMs in reverse dependency order (clients first, then DC).
        Saves VM state to disk for quick resume later.

    .PARAMETER Wait
        Wait for all suspends to complete before returning.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for each VM suspend (default: 60).

    .OUTPUTS
        PSCustomObject with suspend results including VMsSuspended, FailedVMs,
        AlreadyStopped, OverallStatus, Message, and Duration.

    .EXAMPLE
        Suspend-LabVMs

    .EXAMPLE
        Suspend-LabVMs -Wait
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [int]$TimeoutSeconds = 60
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsSuspended = @()
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

        # Step 3: Suspend order: reverse of start (clients first, then DC)
        $suspendOrder = @("SimpleWin11", "SimpleServer", "SimpleDC")

        foreach ($vmName in $suspendOrder) {
            Write-Verbose "Suspending VM '$vmName'..."

            # Check if VM exists and is running
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                continue
            }

            # Skip if not running (can't suspend non-running VMs)
            if ($vm.State -ne "Running") {
                Write-Verbose "VM '$vmName' is not running (state: $($vm.State)), skipping"
                $result.AlreadyStopped += $vmName
                continue
            }

            # Build parameters for Suspend-LabVM
            $suspendParams = @{
                VMName = $vmName
            }

            if ($Wait) {
                $suspendParams.Wait = $true
                $suspendParams.TimeoutSeconds = $TimeoutSeconds
            }

            # Suspend the VM
            try {
                $suspendResult = Suspend-LabVM @suspendParams

                if ($suspendResult.OverallStatus -eq "OK") {
                    $result.VMsSuspended += $vmName
                    Write-Verbose "VM '$vmName' suspended successfully"
                }
                else {
                    $result.FailedVMs += $vmName
                    Write-Warning "Failed to suspend VM '$vmName': $($suspendResult.Message)"
                }
            }
            catch {
                $result.FailedVMs += $vmName
                Write-Error "Error suspending VM '$vmName': $($_.Exception.Message)"
            }
        }

        # Step 4: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Suspended $($result.VMsSuspended.Count) VM(s), $($result.AlreadyStopped.Count) already stopped"
        }
        elseif ($result.VMsSuspended.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Suspended $($result.VMsSuspended.Count) VM(s), failed $($result.FailedVMs.Count), $($result.AlreadyStopped.Count) already stopped"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to suspend any VMs"
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
