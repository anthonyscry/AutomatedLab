function Suspend-LabVM {
    <#
    .SYNOPSIS
        Suspends a SimpleLab virtual machine by saving its state.

    .DESCRIPTION
        Suspends a specified lab VM by saving its current state (memory) to disk.
        The VM can be quickly resumed later without a full boot cycle.

    .PARAMETER VMName
        Name of the virtual machine to suspend.

    .PARAMETER Wait
        Wait for the suspend operation to complete before returning.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for suspend to complete (default: 60).

    .OUTPUTS
        PSCustomObject with suspend results including VMName, PreviousState,
        CurrentState, OverallStatus, Message, and Duration.

    .EXAMPLE
        Suspend-LabVM -VMName dc1

    .EXAMPLE
        Suspend-LabVM -VMName svr1 -Wait
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

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
        VMName = $VMName
        PreviousState = "Unknown"
        CurrentState = "Unknown"
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

        # Step 2: Check if VM exists
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.OverallStatus = "NotFound"
            $result.Message = "VM '$VMName' does not exist"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Record previous state
        $result.PreviousState = $vm.State

        # Step 3: Check if VM can be suspended (must be Running)
        if ($vm.State -ne "Running") {
            $result.OverallStatus = "Failed"
            $result.CurrentState = $vm.State
            $result.Message = "VM '$VMName' cannot be suspended (current state: $($vm.State))"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 4: Suspend the VM
        Write-Verbose "Suspending VM '$VMName'..."

        try {
            Save-VM -Name $VMName -ErrorAction Stop
            Write-Verbose "VM '$VMName' suspend command sent"
        }
        catch {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to suspend VM '$VMName': $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 5: Wait for Saved state if requested
        if ($Wait) {
            Write-Verbose "Waiting for VM '$VMName' to reach Saved state..."

            $waitStart = Get-Date
            $saved = $false

            while ((New-TimeSpan -Start $waitStart -End (Get-Date)).TotalSeconds -lt $TimeoutSeconds) {
                $vmCheck = Get-VM -Name $VMName -ErrorAction SilentlyContinue

                if ($vmCheck -and $vmCheck.State -eq "Saved") {
                    Write-Verbose "VM '$VMName' is now in Saved state"
                    $saved = $true
                    break
                }

                Start-Sleep -Seconds 1
            }

            if ($saved) {
                $result.OverallStatus = "OK"
                $result.Message = "VM suspended successfully"
                $result.CurrentState = "Saved"
            }
            else {
                $result.OverallStatus = "Timeout"
                $result.Message = "Suspend initiated but VM not saved within ${TimeoutSeconds}s"
                # Get current state
                $vmCurrent = Get-VM -Name $VMName -ErrorAction SilentlyContinue
                $result.CurrentState = if ($vmCurrent) { $vmCurrent.State } else { "Unknown" }
            }
        }
        else {
            # No wait, just report initiation
            $result.OverallStatus = "OK"
            $result.Message = "Suspend initiated successfully"
            $result.CurrentState = $vm.State
        }

        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
