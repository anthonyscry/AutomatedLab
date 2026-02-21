function Get-LabVMMetrics {
    <#
    .SYNOPSIS
        Collects all dashboard metrics for a single VM.

    .DESCRIPTION
        Orchestrates collection of snapshot age, disk usage, VM uptime, and
        STIG compliance status for a VM. Returns a single PSCustomObject with
        all metrics. Designed to be called from a background runspace.

    .PARAMETER VMName
        Name of the virtual machine to query.

    .OUTPUTS
        [PSCustomObject] with VMName, SnapshotAge, DiskUsage, UptimeHours,
        STIGStatus properties. Individual properties may be $null when data
        is unavailable.

    .EXAMPLE
        Get-LabVMMetrics -VMName 'dc1'
        Returns complete metrics object for dc1.

    .EXAMPLE
        'dc1', 'svr1' | Get-LabVMMetrics
        Returns metrics objects for both VMs via pipeline.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$VMName
    )

    process {
        foreach ($vm in $VMName) {
            try {
                # Collect snapshot age
                $snapshotAge = Get-LabSnapshotAge -VMName $vm

                # Collect disk usage
                $diskUsage = Get-LabVMDiskUsage -VMName $vm

                # Collect uptime (from Phase 26)
                $uptimeData = Get-LabUptime -ErrorAction SilentlyContinue
                $uptimeHours = if ($uptimeData -and $uptimeData.ElapsedHours) {
                    $uptimeData.ElapsedHours
                } else {
                    $null
                }

                # Collect STIG compliance (from Phase 27 cache)
                $stigData = Get-LabSTIGCompliance -ErrorAction SilentlyContinue
                $stigEntry = $stigData | Where-Object { $_.VMName -eq $vm }
                $stigStatus = if ($stigEntry) {
                    $stigEntry.Status
                } else {
                    'Unknown'
                }

                [pscustomobject]@{
                    VMName          = $vm
                    SnapshotAge     = $snapshotAge         # [int] days or $null
                    DiskUsageGB     = if ($diskUsage) { $diskUsage.FileSizeGB } else { $null }
                    DiskUsagePercent = if ($diskUsage) { $diskUsage.UsagePercent } else { $null }
                    UptimeHours     = $uptimeHours        # [double] or $null
                    STIGStatus      = $stigStatus         # 'Compliant', 'NonCompliant', 'Applying', 'Unknown'
                }
            }
            catch {
                Write-Verbose "[Get-LabVMMetrics] Failed to collect metrics for $vm`: $($_.Exception.Message)"
                # Return partial object with error indicator
                [pscustomobject]@{
                    VMName            = $vm
                    SnapshotAge       = $null
                    DiskUsageGB       = $null
                    DiskUsagePercent  = $null
                    UptimeHours       = $null
                    STIGStatus        = 'Unknown'
                }
            }
        }
    }
}
