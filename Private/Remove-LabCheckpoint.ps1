function Remove-LabCheckpoint {
    <#
    .SYNOPSIS
        Removes all checkpoints for SimpleLab virtual machines.

    .DESCRIPTION
        Removes all checkpoints/snapshots for all lab VMs.
        Must be called before VM removal.

    .OUTPUTS
        PSCustomObject with checkpoint removal results.

    .NOTES
        Internal function - not exported
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        CheckpointsRemoved = 0
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

        # Step 2: Get lab VMs
        $labVMs = @("SimpleDC", "SimpleServer", "SimpleWin11")

        foreach ($vmName in $labVMs) {
            # Check if VM exists
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping checkpoint removal"
                continue
            }

            # Get checkpoints for this VM
            $checkpoints = Get-VMCheckpoint -VMName $vmName -ErrorAction SilentlyContinue

            if ($null -eq $checkpoints -or $checkpoints.Count -eq 0) {
                Write-Verbose "No checkpoints found for VM '$vmName'"
                continue
            }

            # Remove checkpoints
            foreach ($checkpoint in $checkpoints) {
                try {
                    Write-Verbose "Removing checkpoint '$($checkpoint.Name)' from VM '$vmName'..."
                    Remove-VMCheckpoint -VMName $vmName -Name $checkpoint.Name -ErrorAction Stop
                    $result.CheckpointsRemoved++
                }
                catch {
                    Write-Warning "Failed to remove checkpoint '$($checkpoint.Name)' from VM '$vmName': $($_.Exception.Message)"
                    if ($vmName -notin $result.FailedVMs) {
                        $result.FailedVMs += $vmName
                    }
                }
            }
        }

        # Step 3: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Removed $($result.CheckpointsRemoved) checkpoint(s)"
        }
        elseif ($result.CheckpointsRemoved -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Removed $($result.CheckpointsRemoved) checkpoint(s), some failures occurred"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to remove any checkpoints"
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
