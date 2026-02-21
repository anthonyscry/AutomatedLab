function Get-LabPerformanceRecommendation {
    <#
    .SYNOPSIS
        Returns performance optimization recommendations based on metrics analysis.

    .DESCRIPTION
        Get-LabPerformanceRecommendation analyzes performance metrics and provides
        actionable recommendations for optimizing lab operations. Recommendations
        include specific steps to address identified issues.

    .PARAMETER Operation
        Filter recommendations to specific operation type (optional).

    .PARAMETER VMName
        Filter recommendations to specific VM name (optional).

    .PARAMETER Severity
        Filter by severity level: 'Critical', 'Warning', 'Info' (optional).

    .PARAMETER RecentHours
        Number of hours to analyze for recommendations (default: 24).

    .OUTPUTS
        Array of PSCustomobject with Recommendation, Action, Priority, Context fields.

    .EXAMPLE
        Get-LabPerformanceRecommendation -RecentHours 48

    .EXAMPLE
        Get-LabPerformanceRecommendation -Operation 'VMStart' -Severity Critical
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$Operation,

        [string]$VMName,

        [ValidateSet('Critical', 'Warning', 'Info')]
        [string]$Severity,

        [int]$RecentHours = 24
    )

    $performanceConfig = Get-LabPerformanceConfig
    $storagePath = $performanceConfig.StoragePath

    if (-not (Test-Path $storagePath)) {
        Write-Warning "Performance metrics file not found at '$storagePath'"
        return @()
    }

    try {
        $data = Get-Content -Raw -Path $storagePath | ConvertFrom-Json
        $metrics = if ($data.metrics) { @($data.metrics) } else { @() }
    }
    catch {
        Write-Warning "Failed to read performance metrics file '$storagePath': $($_.Exception.Message)"
        return @()
    }

    if ($metrics.Count -eq 0) {
        Write-Warning "No performance metrics available for analysis"
        return @()
    }

    $filteredMetrics = $metrics

    if ($PSBoundParameters.ContainsKey('Operation')) {
        $filteredMetrics = @($filteredMetrics | Where-Object { $_.Operation -eq $Operation })
    }

    if ($PSBoundParameters.ContainsKey('VMName')) {
        $filteredMetrics = @($filteredMetrics | Where-Object { $_.VMName -eq $VMName })
    }

    $baseline = Get-LabPerformanceBaseline -Metrics $metrics

    if ($PSBoundParameters.ContainsKey('Operation')) {
        $baseline = @($baseline | Where-Object { $_.Operation -eq $Operation })
    }

    if ($PSBoundParameters.ContainsKey('VMName')) {
        $baseline = @($baseline | Where-Object { $_.VMName -eq $VMName })
    }

    $insights = Get-LabPerformanceInsights -Metrics $filteredMetrics -Baseline $baseline -RecentHours $RecentHours

    if ($PSBoundParameters.ContainsKey('Severity')) {
        $insights = @($insights | Where-Object { $_.Severity -eq $Severity })
    }

    $recommendations = @()

    foreach ($insight in $insights) {
        $recommendation = switch ($insight.InsightType) {
            'PerformanceDegradation' {
                $details = $insight.Details
                if ($details.RecentAvgMs -gt 30000) {
                    "Consider investigating host resource constraints (CPU, memory, disk I/O)"
                }
                elseif ($insight.Operation -eq 'VMStart') {
                    "Check VM configuration: consider using checkpoints or reducing memory allocation"
                }
                elseif ($insight.Operation -eq 'LabDeploy') {
                    "Consider parallelizing VM deployment or using pre-built golden images"
                }
                else {
                    "Review recent changes to $($insight.VMName) configuration or workload"
                }
            }
            'HighFailureRate' {
                $details = $insight.Details
                if ($details.FailureRate -gt 50) {
                    "Critical: Investigate and resolve root cause immediately - check event logs for errors"
                }
                elseif ($insight.Operation -eq 'VMStart') {
                    "Verify VM configuration and sufficient host resources"
                }
                else {
                    "Review error logs for $($insight.Operation) on $($insight.VMName) to identify common failure patterns"
                }
            }
            'HighVariability' {
                "Investigate resource contention - consider dedicating resources or scheduling operations during off-peak hours"
            }
            'OptimizationOpportunity' {
                if ($insight.Operation -eq 'VMStart') {
                    "Consider using VM checkpoints to reduce startup time, or evaluate VM resource allocation"
                }
                elseif ($insight.Operation -eq 'LabDeploy') {
                    "Use golden images or parallel deployment to reduce deployment time"
                }
                else {
                    "Review $($insight.Operation) implementation for optimization opportunities"
                }
            }
            default {
                "Monitor and investigate $($insight.Operation) on $($insight.VMName)"
            }
        }

        $action = switch ($insight.InsightType) {
            'PerformanceDegradation' {
                "Compare current configuration with baseline period; review recent changes"
            }
            'HighFailureRate' {
                "Check System and Application event logs; verify resource availability"
            }
            'HighVariability' {
                "Monitor host resource usage during operations; consider resource reservations"
            }
            'OptimizationOpportunity' {
                "Analyze operation workflow; identify bottlenecks and optimization candidates"
            }
            default {
                "Continue monitoring and gather more data"
            }
        }

        $recommendations += [pscustomobject]@{
            InsightType    = $insight.InsightType
            Recommendation = $recommendation
            Action         = $action
            Priority       = $insight.Severity
            Context        = @{
                Operation = $insight.Operation
                VMName    = $insight.VMName
                Message   = $insight.Message
                Details   = $insight.Details
            }
        }
    }

    return @($recommendations)
}

