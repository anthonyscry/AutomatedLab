function Restart-LabVMs {
    <#
    .SYNOPSIS
        Restarts all SimpleLab virtual machines.

    .DESCRIPTION
        Restarts all lab VMs in the correct dependency order (DC first, then servers, then clients).
        Optionally waits for all VMs to be fully ready after restart.

    .PARAMETER Force
        Force hard restart vs graceful shutdown for each VM.

    .PARAMETER Wait
        Wait for all VMs to be fully ready after restart.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for each VM startup (default: 600).

    .PARAMETER StabilizationSeconds
        Time to wait after each VM is running for services to stabilize (default: 30).

    .OUTPUTS
        PSCustomObject with restart results including VMsRestarted, FailedVMs, OverallStatus,
        Message, and Duration.

    .EXAMPLE
        Restart-LabVMs

    .EXAMPLE
        Restart-LabVMs -Force -Wait
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds = 600,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$StabilizationSeconds = 30
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsRestarted = @()
        FailedVMs = @()
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

        # Step 3: Restart order: DC first, then other servers, then clients
        $restartOrder = @("dc1", "svr1", "ws1")

        foreach ($vmName in $restartOrder) {
            Write-Verbose "Restarting VM '$vmName'..."

            # Build parameters for Restart-LabVM
            $restartParams = @{
                VMName = $vmName
            }

            if ($Force) {
                $restartParams.Force = $true
            }

            if ($Wait) {
                $restartParams.Wait = $true
                $restartParams.TimeoutSeconds = $TimeoutSeconds
                $restartParams.StabilizationSeconds = $StabilizationSeconds
            }

            # Restart the VM
            try {
                $restartResult = Restart-LabVM @restartParams

                if ($restartResult.OverallStatus -eq "OK") {
                    $result.VMsRestarted += $vmName
                    Write-Verbose "VM '$vmName' restarted successfully"
                }
                elseif ($restartResult.OverallStatus -eq "NotFound") {
                    Write-Verbose "VM '$vmName' does not exist, skipping"
                }
                else {
                    $result.FailedVMs += $vmName
                    Write-Warning "Failed to restart VM '$vmName': $($restartResult.Message)"
                }
            }
            catch {
                $result.FailedVMs += $vmName
                Write-Error "Error restarting VM '$vmName': $($_.Exception.Message)"
            }
        }

        # Step 4: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Restarted $($result.VMsRestarted.Count) VM(s)"
        }
        elseif ($result.VMsRestarted.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Restarted $($result.VMsRestarted.Count) VM(s), failed $($result.FailedVMs.Count)"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to restart any VMs"
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
