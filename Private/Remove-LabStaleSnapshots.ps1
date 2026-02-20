function Remove-LabStaleSnapshots {
    <#
    .SYNOPSIS
        Removes snapshots older than a configurable age threshold.

    .DESCRIPTION
        Uses Get-LabSnapshotInventory to discover all snapshots, filters for
        those exceeding the age threshold, and removes them. Supports -WhatIf
        and -Confirm via ShouldProcess. Returns a structured result with counts
        and details of removed/failed snapshots.

    .PARAMETER OlderThanDays
        Age threshold in days. Snapshots with AgeDays greater than this value
        are considered stale and will be removed. Default: 7.

    .PARAMETER VMName
        Optional list of VM names to filter. Passed through to
        Get-LabSnapshotInventory.

    .OUTPUTS
        PSCustomObject with Removed, Failed, TotalFound, TotalRemoved,
        ThresholdDays, and OverallStatus properties.

    .EXAMPLE
        Remove-LabStaleSnapshots
        # Removes snapshots older than 7 days

    .EXAMPLE
        Remove-LabStaleSnapshots -OlderThanDays 3 -WhatIf
        # Shows what would be removed without actually removing
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [int]$OlderThanDays = 7,

        [Parameter()]
        [string[]]$VMName
    )

    Set-StrictMode -Version Latest

    # Get snapshot inventory
    $inventoryParams = @{}
    if ($PSBoundParameters.ContainsKey('VMName')) {
        $inventoryParams['VMName'] = $VMName
    }
    $allSnapshots = Get-LabSnapshotInventory @inventoryParams

    # Filter for stale snapshots
    $staleSnapshots = @($allSnapshots | Where-Object { $_.AgeDays -gt $OlderThanDays })

    # Initialize tracking arrays
    $removed = @()
    $failed = @()

    if ($staleSnapshots.Count -eq 0) {
        return [PSCustomObject]@{
            Removed       = @()
            Failed        = @()
            TotalFound    = 0
            TotalRemoved  = 0
            ThresholdDays = $OlderThanDays
            OverallStatus = 'NoStale'
        }
    }

    foreach ($snap in $staleSnapshots) {
        $target = "$($snap.CheckpointName) on $($snap.VMName)"
        if ($PSCmdlet.ShouldProcess($target, 'Remove-VMCheckpoint')) {
            try {
                Remove-VMCheckpoint -VMName $snap.VMName -Name $snap.CheckpointName -ErrorAction Stop
                $removed += [PSCustomObject]@{
                    VMName         = $snap.VMName
                    CheckpointName = $snap.CheckpointName
                    AgeDays        = $snap.AgeDays
                }
            }
            catch {
                $failed += [PSCustomObject]@{
                    VMName         = $snap.VMName
                    CheckpointName = $snap.CheckpointName
                    AgeDays        = $snap.AgeDays
                    ErrorMessage   = $_.Exception.Message
                }
            }
        }
    }

    # Determine overall status
    $overallStatus = if ($failed.Count -gt 0 -and $removed.Count -gt 0) {
        'Partial'
    }
    elseif ($failed.Count -gt 0 -and $removed.Count -eq 0) {
        'Partial'
    }
    else {
        'OK'
    }

    return [PSCustomObject]@{
        Removed       = $removed
        Failed        = $failed
        TotalFound    = $staleSnapshots.Count
        TotalRemoved  = $removed.Count
        ThresholdDays = $OlderThanDays
        OverallStatus = $overallStatus
    }
}
