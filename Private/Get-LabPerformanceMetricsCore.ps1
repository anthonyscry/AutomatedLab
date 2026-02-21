function Get-LabPerformanceMetricsCore {
    <#
    .SYNOPSIS
        Core function for querying and aggregating performance metrics.

    .DESCRIPTION
        Get-LabPerformanceMetricsCore reads metrics from the performance log and
        provides aggregation capabilities. Supports filtering by operation, VM name,
        date range, and success status. Calculates statistics like min, max, average,
        and percentile durations.

    .PARAMETER Metrics
        Array of metric objects to process (pipeline input).

    .PARAMETER Operation
        Filter to specific operation type (optional).

    .PARAMETER VMName
        Filter to specific VM name (optional).

    .PARAMETER Success
        Filter to successful or failed operations (optional, null = both).

    .PARAMETER After
        Only include metrics after this DateTime (optional).

    .PARAMETER Before
        Only include metrics before this DateTime (optional).

    .OUTPUTS
        PSCustomObject with aggregated metrics including Min, Max, Avg, Percentile50,
        Percentile90, Percentile95, TotalCount, SuccessCount, FailureCount.

    .EXAMPLE
        $metrics = Get-LabPerformanceMetricsCore -Metrics $allMetrics -Operation 'VMStart'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject[]]$Metrics,

        [string]$Operation,

        [string]$VMName,

        [bool]$Success,

        [DateTime]$After,

        [DateTime]$Before
    )

    begin {
        $allMetrics = @()
    }

    process {
        $allMetrics += $Metrics
    }

    end {
        if ($null -eq $allMetrics -or $allMetrics.Count -eq 0) {
            return [pscustomobject]@{
                Operation          = $Operation
                VMName             = $VMName
                Min                = $null
                Max                = $null
                Avg                = $null
                Percentile50       = $null
                Percentile90       = $null
                Percentile95       = $null
                TotalCount         = 0
                SuccessCount       = 0
                FailureCount       = 0
                SuccessRatePercent = 0
            }
        }

        $filtered = @($allMetrics)

        if ($PSBoundParameters.ContainsKey('Operation')) {
            $filtered = @($filtered | Where-Object { $_.Operation -eq $Operation })
        }

        if ($PSBoundParameters.ContainsKey('VMName')) {
            $filtered = @($filtered | Where-Object { $_.VMName -eq $VMName })
        }

        if ($PSBoundParameters.ContainsKey('Success')) {
            $filtered = @($filtered | Where-Object { $_.Success -eq $Success })
        }

        if ($PSBoundParameters.ContainsKey('After')) {
            $filtered = @($filtered | Where-Object {
                try {
                    [DateTime]::Parse($_.Timestamp) -gt $After
                }
                catch {
                    $false
                }
            })
        }

        if ($PSBoundParameters.ContainsKey('Before')) {
            $filtered = @($filtered | Where-Object {
                try {
                    [DateTime]::Parse($_.Timestamp) -lt $Before
                }
                catch {
                    $false
                }
            })
        }

        $durations = @($filtered | Where-Object { $null -ne $_.Duration } | ForEach-Object { [long]$_.Duration })

        $totalCount = $filtered.Count
        $successCount = @($filtered | Where-Object { $_.Success -eq $true }).Count
        $failureCount = @($filtered | Where-Object { $_.Success -eq $false }).Count

        if ($durations.Count -gt 0) {
            $sortedDurations = @($durations | Sort-Object)

            $min = $sortedDurations[0]
            $max = $sortedDurations[-1]
            $avg = ($sortedDurations | Measure-Object -Average).Average

            $p50Index = [math]::Floor(($sortedDurations.Count - 1) * 0.50)
            $p90Index = [math]::Floor(($sortedDurations.Count - 1) * 0.90)
            $p95Index = [math]::Floor(($sortedDurations.Count - 1) * 0.95)

            $percentile50 = $sortedDurations[$p50Index]
            $percentile90 = $sortedDurations[$p90Index]
            $percentile95 = $sortedDurations[$p95Index]
        }
        else {
            $min = $null
            $max = $null
            $avg = $null
            $percentile50 = $null
            $percentile90 = $null
            $percentile95 = $null
        }

        $successRatePercent = if ($totalCount -gt 0) {
            [math]::Round(($successCount / $totalCount) * 100, 2)
        }
        else {
            0
        }

        [pscustomobject]@{
            Operation          = $Operation
            VMName             = $VMName
            Min                = $min
            Max                = $max
            Avg                = if ($null -ne $avg) { [math]::Round($avg, 2) } else { $null }
            Percentile50       = $percentile50
            Percentile90       = $percentile90
            Percentile95       = $percentile95
            TotalCount         = $totalCount
            SuccessCount       = $successCount
            FailureCount       = $failureCount
            SuccessRatePercent = $successRatePercent
        }
    }
}
