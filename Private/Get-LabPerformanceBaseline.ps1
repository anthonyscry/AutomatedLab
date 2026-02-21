function Get-LabPerformanceBaseline {
    <#
    .SYNOPSIS
        Calculates historical baseline performance metrics.

    .DESCRIPTION
        Get-LabPerformanceBaseline computes baseline statistics from historical
        performance data. Baselines are calculated per operation and VM combination,
        providing reference values for comparison. Uses median (p50) as the baseline
        value for typical performance.

    .PARAMETER Metrics
        Array of metric objects to analyze.

    .PARAMETER Operation
        Filter to specific operation type (optional, null = all operations).

    .PARAMETER VMName
        Filter to specific VM name (optional, null = all VMs).

    .OUTPUTS
        Array of PSCustomObject with Operation, VMName, BaselineMs (p50),
        ThresholdMs (p90), SampleCount fields.

    .EXAMPLE
        $baseline = Get-LabPerformanceBaseline -Metrics $metrics -Operation 'VMStart'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(ValueFromPipeline)]
        [pscustomobject[]]$Metrics,

        [string]$Operation,

        [string]$VMName
    )

    begin {
        $allMetrics = @()
    }

    process {
        $allMetrics += $Metrics
    }

    end {
        if ($null -eq $allMetrics -or $allMetrics.Count -eq 0) {
            return @()
        }

        $filtered = @($allMetrics | Where-Object { $_.Success -eq $true })

        if ($PSBoundParameters.ContainsKey('Operation')) {
            $filtered = @($filtered | Where-Object { $_.Operation -eq $Operation })
        }

        if ($PSBoundParameters.ContainsKey('VMName')) {
            $filtered = @($filtered | Where-Object { $_.VMName -eq $VMName })
        }

        # Group by operation and VM name
        $groups = $filtered | Group-Object -Property { "$($_.Operation)|$($_.VMName)" }

        $baselines = @()

        foreach ($group in $groups) {
            $durations = @($group.Group | ForEach-Object { [long]$_.Duration })

            if ($durations.Count -eq 0) {
                continue
            }

            $sortedDurations = @($durations | Sort-Object)

            $p50Index = [math]::Floor(($sortedDurations.Count - 1) * 0.50)
            $p90Index = [math]::Floor(($sortedDurations.Count - 1) * 0.90)
            $p95Index = [math]::Floor(($sortedDurations.Count - 1) * 0.95)

            $parts = $group.Name -split '\|'
            $op = $parts[0]
            $vm = $parts[1]

            $baselines += [pscustomobject]@{
                Operation     = $op
                VMName        = $vm
                BaselineMs    = $sortedDurations[$p50Index]
                ThresholdMs   = $sortedDurations[$p90Index]
                CriticalMs    = $sortedDurations[$p95Index]
                SampleCount   = $sortedDurations.Count
            }
        }

        return @($baselines)
    }
}
