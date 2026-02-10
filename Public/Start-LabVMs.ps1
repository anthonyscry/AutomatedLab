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
        $startOrder = @("SimpleDC", "SimpleServer", "SimpleWin11")

        foreach ($vmName in $startOrder) {
            # Check if VM exists
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                continue
            }

            # Check current state
            if ($vm.State -eq "Running") {
                Write-Verbose "VM '$vmName' is already running"
                $result.AlreadyRunning += $vmName
                continue
            }

            # Start the VM
            try {
                Write-Verbose "Starting VM '$vmName'..."
                Start-VM -Name $vmName -ErrorAction Stop
                $result.VMsStarted += $vmName
                Write-Verbose "VM '$vmName' start command sent"
            }
            catch {
                Write-Error "Failed to start VM '$vmName': $($_.Exception.Message)"
                $result.FailedVMs += $vmName
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
