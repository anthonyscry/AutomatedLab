function Restore-LabCheckpoint {
    <#
    .SYNOPSIS
        Restores all SimpleLab virtual machines to a previous checkpoint.

    .DESCRIPTION
        Restores all lab VMs to a specified checkpoint. VMs are restored in
        reverse dependency order (clients first, then DC). All VMs must have
        a checkpoint with the specified name.

    .PARAMETER CheckpointName
        Name of the checkpoint to restore.

    .PARAMETER SwitchName
        Name of the virtual switch (default: "SimpleLab").

    .OUTPUTS
        PSCustomObject with restore results.

    .EXAMPLE
        Restore-LabCheckpoint -CheckpointName "BeforeConfigChange"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CheckpointName,

        [Parameter()]
        [string]$SwitchName = "SimpleLab"
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        CheckpointName = $CheckpointName
        VMsRestored = @()
        FailedVMs = @()
        SkippedVMs = @()
        OverallStatus = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.OverallStatus = "Failed"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Get VM configurations
        $vmConfigs = Get-LabVMConfig
        if ($null -eq $vmConfigs) {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to retrieve VM configurations"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Restore order: reverse (clients first, then DC)
        $restoreOrder = @("ws1", "svr1", "dc1")

        foreach ($vmName in $restoreOrder) {
            # Check if VM exists
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                $result.SkippedVMs += $vmName
                continue
            }

            # Check if checkpoint exists for this VM
            $checkpoint = Get-VMCheckpoint -VMName $vmName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $CheckpointName }
            if ($null -eq $checkpoint) {
                Write-Warning "Checkpoint '$CheckpointName' not found for VM '$vmName'"
                $result.SkippedVMs += $vmName
                continue
            }

            # Restore checkpoint
            try {
                Write-Verbose "Restoring checkpoint '$CheckpointName' for VM '$vmName'..."
                Restore-VMCheckpoint -Name $vmName -SnapshotName $CheckpointName -ErrorAction Stop
                $result.VMsRestored += $vmName
                Write-Verbose "Checkpoint restored for VM '$vmName'"
            }
            catch {
                Write-Error "Failed to restore checkpoint for VM '$vmName': $($_.Exception.Message)"
                $result.FailedVMs += $vmName
            }
        }

        # Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0 -and $result.VMsRestored.Count -gt 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Restored checkpoint '$CheckpointName' for $($result.VMsRestored.Count) VM(s)"
        }
        elseif ($result.VMsRestored.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Restored checkpoint for $($result.VMsRestored.Count) VM(s), failed $($result.FailedVMs.Count), skipped $($result.SkippedVMs.Count)"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to restore checkpoint for any VMs"
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
