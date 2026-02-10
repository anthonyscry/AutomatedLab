function Resume-LabVM {
    <#
    .SYNOPSIS
        Resumes a suspended SimpleLab virtual machine.

    .DESCRIPTION
        Resumes a suspended (Saved) lab VM. This is faster than a cold boot
        since the VM state is preserved in memory.

    .PARAMETER VMName
        Name of the virtual machine to resume.

    .PARAMETER Wait
        Wait for the VM to be fully ready after resume.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for VM to be ready (default: 180).
        Resume is faster than cold boot, so default is lower.

    .OUTPUTS
        PSCustomObject with resume results including VMName, PreviousState,
        CurrentState, OverallStatus, Message, and Duration.

    .EXAMPLE
        Resume-LabVM -VMName SimpleDC

    .EXAMPLE
        Resume-LabVM -VMName SimpleServer -Wait
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$VMName,

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [int]$TimeoutSeconds = 180
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
        $wasSaved = $vm.State -eq "Saved"

        # Step 3: Start the VM (works for both Saved and Off states)
        Write-Verbose "Resuming VM '$VMName' (current state: $($vm.State))..."

        try {
            Start-VM -Name $VMName -ErrorAction Stop
            Write-Verbose "VM '$VMName' start command sent"
        }
        catch {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to resume VM '$VMName': $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 4: Wait for VM to be ready if requested
        if ($Wait) {
            Write-Verbose "Waiting for VM '$VMName' to be ready..."

            $waitStart = Get-Date
            $ready = $false

            while ((New-TimeSpan -Start $waitStart -End (Get-Date)).TotalSeconds -lt $TimeoutSeconds) {
                $vmCheck = Get-VM -Name $VMName -ErrorAction SilentlyContinue

                if ($vmCheck -and $vmCheck.State -eq "Running" -and $vmCheck.Heartbeat -eq "Ok") {
                    Write-Verbose "VM '$VMName' is Running and Heartbeat OK"
                    $ready = $true
                    break
                }

                Start-Sleep -Seconds 3
            }

            if ($ready) {
                $result.OverallStatus = "OK"
                $result.Message = if ($wasSaved) { "VM resumed from saved state" } else { "VM started successfully" }
                $result.CurrentState = "Running"
            }
            else {
                $result.OverallStatus = "Timeout"
                $result.Message = "Resume initiated but VM not ready within ${TimeoutSeconds}s"
                # Get current state
                $vmCurrent = Get-VM -Name $VMName -ErrorAction SilentlyContinue
                $result.CurrentState = if ($vmCurrent) { $vmCurrent.State } else { "Unknown" }
            }
        }
        else {
            # No wait, just report initiation
            $result.OverallStatus = "OK"
            if ($wasSaved) {
                $result.Message = "Resume from saved state initiated"
            }
            else {
                $result.Message = "VM start initiated (was not in saved state)"
            }
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
