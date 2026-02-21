function Get-LabSnapshotAge {
    <#
    .SYNOPSIS
        Returns the age of the oldest snapshot for a VM in days.

    .DESCRIPTION
        Queries Get-VMSnapshot for the specified VM and calculates the age
        of the oldest snapshot based on CreationTime. Returns null if no
        snapshots exist or on error.

    .PARAMETER VMName
        Name of the virtual machine to query.

    .OUTPUTS
        [int] Age in days, or $null if no snapshots or on error.

    .EXAMPLE
        Get-LabSnapshotAge -VMName 'dc1'
        Returns the age of the oldest snapshot for dc1 in days.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$VMName
    )

    try {
        $snapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue
        if (-not $snapshots -or @($snapshots).Count -eq 0) {
            return $null
        }

        # Find oldest snapshot (earliest CreationTime)
        $oldest = $snapshots | Sort-Object -Property CreationTime | Select-Object -First 1
        $age = (Get-Date) - $oldest.CreationTime
        return [int]$age.TotalDays
    }
    catch {
        Write-Verbose "[Get-LabSnapshotAge] Failed to query snapshots for $VMName`: $($_.Exception.Message)"
        return $null
    }
}
