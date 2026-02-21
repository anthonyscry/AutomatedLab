function Get-LabUsageTrendsCore {
    <#
    .SYNOPSIS
        Aggregates lab usage data into time-based trends.

    .DESCRIPTION
        Get-LabUsageTrendsCore processes analytics events and current VM metrics
        to produce aggregated usage trends grouped by time period. Calculates
        deploy counts, total uptime hours, average VM resource usage, and
        operation frequency.

    .PARAMETER Events
        Analytics events array to process.

    .PARAMETER Period
        Grouping period: 'Day', 'Week', 'Month'.

    .PARAMETER VMMetrics
        Current VM metrics to include in trends (optional).

    .OUTPUTS
        [pscustomobject[]] with PeriodStart, PeriodEnd, Deploys, Teardowns,
        TotalUptimeHours, AvgCPU, AvgMemoryGB, AvgDiskGB properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]]$Events,

        [Parameter(Mandatory)]
        [ValidateSet('Day', 'Week', 'Month')]
        [string]$Period,

        [pscustomobject[]]$VMMetrics = @()
    )

    $grouped = @{}

    foreach ($event in $Events) {
        try {
            $timestamp = [DateTime]::Parse($event.Timestamp)
        }
        catch {
            continue
        }

        $periodKey = switch ($Period) {
            'Day'   { $timestamp.ToString('yyyy-MM-dd') }
            'Week'  {
                $culture = [System.Globalization.CultureInfo]::InvariantCulture
                $calendar = $culture.Calendar
                $weekRule = $calendar.GetWeekOfYear($timestamp, [System.Globalization.CalendarWeekRule]::FirstDay, [DayOfWeek]::Monday)
                "$($timestamp.Year)-W$($weekRule.ToString('00'))"
            }
            'Month' { $timestamp.ToString('yyyy-MM') }
        }

        if (-not $grouped.ContainsKey($periodKey)) {
            $grouped[$periodKey] = @{
                PeriodStart   = $timestamp
                PeriodEnd     = $timestamp
                Deploys       = 0
                Teardowns     = 0
                TotalUptime   = 0.0
                VMMetrics     = @()
            }
        }

        $group = $grouped[$periodKey]

        if ($timestamp -lt $group.PeriodStart) {
            $group.PeriodStart = $timestamp
        }
        if ($timestamp -gt $group.PeriodEnd) {
            $group.PeriodEnd = $timestamp
        }

        switch ($event.EventType) {
            'LabDeployed' { $group.Deploys++ }
            'LabTeardown' { $group.Teardowns++ }
        }

        if ($event.Metadata -and $event.Metadata.DurationSeconds) {
            $group.TotalUptime += $event.Metadata.DurationSeconds / 3600.0
        }
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($key in $grouped.Keys | Sort-Object) {
        $group = $grouped[$key]

        $result = [pscustomobject]@{
            Period         = $key
            PeriodStart    = $group.PeriodStart
            PeriodEnd      = $group.PeriodEnd
            Deploys        = $group.Deploys
            Teardowns      = $group.Teardowns
            TotalUptimeHours = [math]::Round($group.TotalUptime, 2)
        }

        if ($VMMetrics.Count -gt 0) {
            $periodMetrics = $VMMetrics | Where-Object {
                $metricTime = $_.CollectedAt ?? $_.Timestamp ?? [DateTime]::Now
                $metricTime -ge $group.PeriodStart -and $metricTime -le $group.PeriodEnd
            }

            if ($periodMetrics) {
                $result.AvgMemoryGB = if (($periodMetrics | Where-Object { $_.MemoryGB }) ) {
                    [math]::Round(($periodMetrics | Where-Object { $_.MemoryGB } | Measure-Object -Property MemoryGB -Average).Average, 2)
                } else { $null }

                $result.AvgDiskGB = if (($periodMetrics | Where-Object { $_.DiskGB })) {
                    [math]::Round(($periodMetrics | Where-Object { $_.DiskGB } | Measure-Object -Property DiskGB -Average).Average, 2)
                } else { $null }

                $result.AvgDiskUsagePercent = if (($periodMetrics | Where-Object { $_.DiskUsagePercent })) {
                    [math]::Round(($periodMetrics | Where-Object { $_.DiskUsagePercent } | Measure-Object -Property DiskUsagePercent -Average).Average, 2)
                } else { $null }
            }
        }

        $results.Add($result)
    }

    return @($results)
}
