function Get-LabUsageTrends {
    <#
    .SYNOPSIS
        Retrieves lab usage trends over time.

    .DESCRIPTION
        Get-LabUsageTrends analyzes analytics events to display lab usage patterns
        including deployment frequency, uptime hours, and resource consumption.
        Trends can be grouped by day, week, or month for different levels of
        granularity.

    .PARAMETER Period
        Time period for grouping: 'Day' (default), 'Week', 'Month'.

    .PARAMETER Days
        Number of recent days to analyze (default 30).

    .PARAMETER LabName
        Filter to events for a specific lab (optional).

    .PARAMETER IncludeCurrentMetrics
        Include current VM metrics in trend calculations (switch).

    .EXAMPLE
        Get-LabUsageTrends
        Returns daily usage trends for the last 30 days.

    .EXAMPLE
        Get-LabUsageTrends -Period Week -Days 90
        Returns weekly usage trends for the last 90 days.

    .EXAMPLE
        Get-LabUsageTrends -LabName 'AutomatedLab' -Period Month
        Returns monthly usage trends for AutomatedLab.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [ValidateSet('Day', 'Week', 'Month')]
        [string]$Period = 'Day',

        [int]$Days = 30,

        [string]$LabName,

        [switch]$IncludeCurrentMetrics
    )

    $afterDate = (Get-Date).AddDays(-$Days)

    $getAnalyticsParams = @{
        After = $afterDate
    }

    if ($PSBoundParameters.ContainsKey('LabName')) {
        $getAnalyticsParams.LabName = $LabName
    }

    $events = Get-LabAnalytics @getAnalyticsParams

    $vmMetrics = @()
    if ($IncludeCurrentMetrics) {
        $vmMetrics = Get-LabVMMetrics -VMName $GlobalLabConfig.Lab.CoreVMNames -ErrorAction SilentlyContinue
    }

    $trends = Get-LabUsageTrendsCore -Events $events -Period $Period -VMMetrics $vmMetrics

    return $trends
}
