function Get-LabPerformanceInsights {
    <#
    .SYNOPSIS
        Analyzes performance metrics for anomalies and optimization opportunities.

    .DESCRIPTION
        Get-LabPerformanceInsights compares recent performance against historical
        baselines to identify degradation, anomalies, and optimization opportunities.
        Provides actionable recommendations for improving lab performance.

    .PARAMETER Metrics
        Array of metric objects to analyze.

    .PARAMETER Baseline
        Array of baseline objects from Get-LabPerformanceBaseline (optional).

    .PARAMETER RecentHours
        Number of hours to consider as "recent" for comparison (default: 24).

    .OUTPUTS
        Array of PSCustomObject with InsightType, Severity, Operation, VMName,
        Message, Details fields.

    .EXAMPLE
        $insights = Get-LabPerformanceInsights -Metrics $metrics -RecentHours 24
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(ValueFromPipeline)]
        [pscustomobject[]]$Metrics,

        [pscustomobject[]]$Baseline,

        [int]$RecentHours = 24
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

        $insights = @()
        $cutoffDate = (Get-Date).AddHours(-$RecentHours)

        # Calculate baseline if not provided
        if ($null -eq $Baseline -or $Baseline.Count -eq 0) {
            $Baseline = Get-LabPerformanceBaseline -Metrics $allMetrics
        }

        # Get recent metrics
        $recentMetrics = @($allMetrics | Where-Object {
            try {
                [DateTime]::Parse($_.Timestamp) -gt $cutoffDate
            }
            catch {
                $false
            }
        })

        # Analyze by operation/VM combination
        $groups = $recentMetrics | Group-Object -Property { "$($_.Operation)|$($_.VMName)" }

        foreach ($group in $groups) {
            $parts = $group.Name -split '\|'
            $op = $parts[0]
            $vm = $parts[1]

            $baseline = $Baseline | Where-Object { $_.Operation -eq $op -and $_.VMName -eq $vm }

            if ($null -eq $baseline) {
                continue
            }

            $recentDurations = @($group.Group | ForEach-Object { [long]$_.Duration })
            $recentAvg = if ($recentDurations.Count -gt 0) {
                ($recentDurations | Measure-Object -Average).Average
            }
            else {
                0
            }

            $failedCount = @($group.Group | Where-Object { $_.Success -eq $false }).Count
            $totalCount = $group.Group.Count
            $failureRate = if ($totalCount -gt 0) { ($failedCount / $totalCount) * 100 } else { 0 }

            # Check for performance degradation
            if ($recentAvg -gt $baseline.ThresholdMs) {
                $severity = if ($recentAvg -gt $baseline.CriticalMs) { 'Critical' } else { 'Warning' }
                $percentOver = [math]::Round((($recentAvg - $baseline.BaselineMs) / $baseline.BaselineMs) * 100, 1)

                $insights += [pscustomobject]@{
                    InsightType = 'PerformanceDegradation'
                    Severity    = $severity
                    Operation   = $op
                    VMName      = $vm
                    Message     = "$op on $vm is ${percentOver}% slower than baseline"
                    Details     = @{
                        BaselineMs  = $baseline.BaselineMs
                        RecentAvgMs = [math]::Round($recentAvg, 2)
                        ThresholdMs = $baseline.ThresholdMs
                    }
                }
            }

            # Check for high failure rate
            if ($failureRate -gt 10) {
                $severity = if ($failureRate -gt 25) { 'Critical' } else { 'Warning' }

                $insights += [pscustomobject]@{
                    InsightType = 'HighFailureRate'
                    Severity    = $severity
                    Operation   = $op
                    VMName      = $vm
                    Message     = "$op on $vm has a ${failureRate}% failure rate"
                    Details     = @{
                        FailureRate = [math]::Round($failureRate, 2)
                        FailedCount = $failedCount
                        TotalCount  = $totalCount
                    }
                }
            }

            # Check for high variability (using coefficient of variation)
            if ($recentDurations.Count -gt 2) {
                $stdDev = 0
                $avg = ($recentDurations | Measure-Object -Average).Average
                foreach ($d in $recentDurations) {
                    $stdDev += [math]::Pow($d - $avg, 2)
                }
                $stdDev = [math]::Sqrt($stdDev / $recentDurations.Count)

                $cv = if ($avg -gt 0) { ($stdDev / $avg) * 100 } else { 0 }

                if ($cv -gt 50) {
                    $insights += [pscustomobject]@{
                        InsightType = 'HighVariability'
                        Severity    = 'Info'
                        Operation   = $op
                        VMName      = $vm
                        Message     = "$op on $vm shows high performance variability"
                        Details     = @{
                            CoefficientOfVariation = [math]::Round($cv, 2)
                            StandardDeviation      = [math]::Round($stdDev, 2)
                            AverageMs              = [math]::Round($avg, 2)
                        }
                    }
                }
            }
        }

        # Check for optimization opportunities
        $slowOperations = $allMetrics | Where-Object { $_.Success -eq $true } |
            Group-Object -Property Operation |
            ForEach-Object {
                $durations = @($_.Group | ForEach-Object { [long]$_.Duration })
                $avg = ($durations | Measure-Object -Average).Average
                [pscustomobject]@{
                    Operation  = $_.Name
                    AvgMs      = $avg
                    Count      = $_.Count
                }
            } |
            Sort-Object -Property AvgMs -Descending |
            Select-Object -First 3

        foreach ($slowOp in $slowOperations) {
            if ($slowOp.AvgMs -gt 10000) {
                $insights += [pscustomobject]@{
                    InsightType = 'OptimizationOpportunity'
                    Severity    = 'Info'
                    Operation   = $slowOp.Operation
                    VMName      = 'All'
                    Message     = "$($slowOp.Operation) operations average $($slowOp.AvgMs)ms - consider optimization"
                    Details     = @{
                        AverageMs = [math]::Round($slowOp.AvgMs, 2)
                        Count     = $slowOp.Count
                    }
                }
            }
        }

        return @($insights | Sort-Object -Property @{ Expression = {
                switch ($_.Severity) {
                    'Critical' { 0 }
                    'Warning' { 1 }
                    'Info' { 2 }
                    default { 3 }
                }
            }; Descending = $false }, InsightType)
    }
}
