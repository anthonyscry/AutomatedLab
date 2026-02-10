function Restart-LabVM {
    <#
    .SYNOPSIS
        Restarts a single SimpleLab virtual machine.

    .DESCRIPTION
        Restarts a specified lab VM by stopping and starting it.
        Supports graceful or forced restart, with optional waiting for the VM to be fully ready.

    .PARAMETER VMName
        Name of the virtual machine to restart.

    .PARAMETER Force
        Force turn off the VM instead of graceful shutdown.

    .PARAMETER Wait
        Wait for the VM to be fully ready (Running + Heartbeat OK) after restart.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for VM startup (default: 300).

    .PARAMETER StabilizationSeconds
        Time to wait after VM is running for services to stabilize (default: 30).

    .OUTPUTS
        PSCustomObject with restart results including VMName, PreviousState, CurrentState,
        OverallStatus, Message, Duration, StopDuration, and StartDuration.

    .EXAMPLE
        Restart-LabVM -VMName SimpleDC

    .EXAMPLE
        Restart-LabVM -VMName SimpleDC -Force

    .EXAMPLE
        Restart-LabVM -VMName SimpleServer -Wait
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$VMName,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [int]$TimeoutSeconds = 300,

        [Parameter()]
        [int]$StabilizationSeconds = 30
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
        StopDuration = $null
        StartDuration = $null
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
        $wasRunning = $vm.State -eq "Running"

        # Step 3: Stop the VM if it's running or in other active states
        $stopStart = Get-Date

        if ($vm.State -ne "Off") {
            Write-Verbose "Stopping VM '$VMName' (current state: $($vm.State))..."

            try {
                if ($Force -or $vm.State -in @("Saved", "Paused", "Critical")) {
                    # Force turn off for saved, paused, or critical states
                    Write-Verbose "Using force turn off for VM '$VMName'"
                    Stop-VM -Name $VMName -TurnOff -Force -ErrorAction Stop
                }
                else {
                    # Graceful shutdown for running VMs
                    Write-Verbose "Using graceful shutdown for VM '$VMName'"
                    Stop-VM -Name $VMName -Force -ErrorAction Stop
                }

                # Wait for Off state with timeout
                $stopWaitStart = Get-Date
                $stopTimeout = 60
                $offStateReached = $false

                while ((New-TimeSpan -Start $stopWaitStart -End (Get-Date)).TotalSeconds -lt $stopTimeout) {
                    $vmCheck = Get-VM -Name $VMName -ErrorAction SilentlyContinue
                    if ($vmCheck -and $vmCheck.State -eq "Off") {
                        $offStateReached = $true
                        Write-Verbose "VM '$VMName' is now Off"
                        break
                    }
                    Start-Sleep -Seconds 1
                }

                if (-not $offStateReached) {
                    Write-Warning "VM '$VMName' did not reach Off state within ${stopTimeout}s, attempting force turn off"
                    try {
                        Stop-VM -Name $VMName -TurnOff -Force -ErrorAction Stop | Out-Null
                        Start-Sleep -Seconds 2
                    }
                    catch {
                        $result.OverallStatus = "Failed"
                        $result.Message = "Failed to stop VM '$VMName': $($_.Exception.Message)"
                        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                        $result.StopDuration = (New-TimeSpan -Start $stopStart -End (Get-Date))
                        return $result
                    }
                }
            }
            catch {
                $result.OverallStatus = "Failed"
                $result.Message = "Failed to stop VM '$VMName': $($_.Exception.Message)"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                $result.StopDuration = (New-TimeSpan -Start $stopStart -End (Get-Date))
                return $result
            }
        }
        else {
            Write-Verbose "VM '$VMName' is already Off"
        }

        $result.StopDuration = (New-TimeSpan -Start $stopStart -End (Get-Date))

        # Step 4: Start the VM
        $startStart = Get-Date

        Write-Verbose "Starting VM '$VMName'..."

        try {
            Start-VM -Name $VMName -ErrorAction Stop
            Write-Verbose "VM '$VMName' start command sent"
        }
        catch {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to start VM '$VMName': $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            $result.StartDuration = (New-TimeSpan -Start $startStart -End (Get-Date))
            return $result
        }

        # Step 5: Wait for VM to be ready if requested
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

                Start-Sleep -Seconds 5
            }

            if ($ready) {
                # Stabilization period for services
                if ($StabilizationSeconds -gt 0) {
                    Write-Verbose "Waiting ${StabilizationSeconds}s for service stabilization..."
                    Start-Sleep -Seconds $StabilizationSeconds
                }

                $result.OverallStatus = "OK"
                $result.Message = "Restarted successfully and ready"
            }
            else {
                $result.OverallStatus = "Timeout"
                $result.Message = "Restart initiated but VM not ready within ${TimeoutSeconds}s"
            }
        }
        else {
            # No wait, just report initiation
            $result.OverallStatus = "OK"
            $result.Message = "Restart initiated successfully"
        }

        # Get final state
        $vmFinal = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vmFinal) {
            $result.CurrentState = $vmFinal.State
        }

        $result.StartDuration = (New-TimeSpan -Start $startStart -End (Get-Date))
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
