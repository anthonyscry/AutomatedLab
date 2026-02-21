function Get-LabResourceTrendCore {
    <#
    .SYNOPSIS
        Aggregates VM resource metrics into time-based trends.

    .DESCRIPTION
        Get-LabResourceTrendCore processes current VM metrics and historical
        analytics events to produce resource utilization trends grouped by
        time period. Calculates average and peak values for CPU, memory,
        and disk usage across all VMs.

    .PARAMETER VMMetrics
        Current VM metrics array to process.

    .PARAMETER AnalyticsEvents
        Historical analytics events for trend context (optional).

    .PARAMETER Period
        Grouping period: 'Hour', 'Day', 'Week'.

    .OUTPUTS
        [pscustomobject[]] with PeriodStart, PeriodEnd, AvgCPU, AvgMemoryGB,
        AvgDiskGB, PeakCPU, PeakMemoryGB, PeakDiskGB, VMCount properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [pscustomobject[]]$VMMetrics = @(),

        [pscustomobject[]]$AnalyticsEvents = @(),

        [Parameter(Mandatory = $false)]
        [ValidateSet('Hour', 'Day', 'Week')]
        [string]$Period = 'Day'
    )

    if ($null -eq $VMMetrics -or $VMMetrics.Count -eq 0) {
        Write-Warning "No VM metrics provided for trend analysis"
        return [System.Object[]]::new(0)
    }

    $now = Get-Date
    $grouped = @{}

    foreach ($vm in $VMMetrics) {
        $timestamp = if ($vm.CollectedAt) {
            [DateTime]::Parse($vm.CollectedAt)
        } else {
            $now
        }

        $periodKey = switch ($Period) {
            'Hour' {
                "$($timestamp.ToString('yyyy-MM-dd HH')):00"
            }
            'Day' {
                $timestamp.ToString('yyyy-MM-dd')
            }
            'Week' {
                $culture = [System.Globalization.CultureInfo]::InvariantCulture
                $calendar = $culture.Calendar
                $weekRule = $calendar.GetWeekOfYear($timestamp, [System.Globalization.CalendarWeekRule]::FirstDay, [DayOfWeek]::Monday)
                "$($timestamp.Year)-W$($weekRule.ToString('00'))"
            }
        }

        if (-not $grouped.ContainsKey($periodKey)) {
            $grouped[$periodKey] = @{
                PeriodStart  = $timestamp
                PeriodEnd    = $timestamp
                CPUSamples   = [System.Collections.Generic.List[double]]::new()
                MemorySamples = [System.Collections.Generic.List[double]]::new()
                DiskSamples   = [System.Collections.Generic.List[double]]::new()
            }
        }

        $group = $grouped[$periodKey]

        if ($timestamp -lt $group.PeriodStart) {
            $group.PeriodStart = $timestamp
        }
        if ($timestamp -gt $group.PeriodEnd) {
            $group.PeriodEnd = $timestamp
        }

        # Extract CPU/memory/disk values from VM metrics object
        # The metrics object might have different property names
        $cpuValue = if ($vm.CPUPercent -ge 0) { [double]$vm.CPUPercent }
                    elseif ($vm.CPU -ge 0) { [double]$vm.CPU }
                    else { 0 }

        $memoryValue = if ($vm.MemoryGB -ge 0) { [double]$vm.MemoryGB }
                       elseif ($vm.Memory -ge 0) { [double]$vm.Memory / 1024 }
                       else { 0 }

        $diskValue = if ($vm.DiskUsagePercent -ge 0) { [double]$vm.DiskUsagePercent }
                    elseif ($vm.DiskGB -ge 0) { [double]$vm.DiskGB }
                    elseif ($vm.DiskUsageGB -ge 0) { [double]$vm.DiskUsageGB }
                    else { 0 }

        if ($cpuValue -gt 0) {
            $group.CPUSamples.Add($cpuValue)
        }
        if ($memoryValue -gt 0) {
            $group.MemorySamples.Add($memoryValue)
        }
        if ($diskValue -gt 0) {
            $group.DiskSamples.Add($diskValue)
        }
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($key in $grouped.Keys | Sort-Object) {
        $group = $grouped[$key]

        $avgCPU = if ($group.CPUSamples.Count -gt 0) {
            [math]::Round(($group.CPUSamples | Measure-Object -Average).Average, 1)
        } else { 0.0 }

        $avgMemory = if ($group.MemorySamples.Count -gt 0) {
            [math]::Round(($group.MemorySamples | Measure-Object -Average).Average, 2)
        } else { 0.0 }

        $avgDisk = if ($group.DiskSamples.Count -gt 0) {
            [math]::Round(($group.DiskSamples | Measure-Object -Average).Average, 2)
        } else { 0.0 }

        $peakCPU = if ($group.CPUSamples.Count -gt 0) {
            [math]::Round(($group.CPUSamples | Measure-Object -Maximum).Maximum, 1)
        } else { 0.0 }

        $peakMemory = if ($group.MemorySamples.Count -gt 0) {
            [math]::Round(($group.MemorySamples | Measure-Object -Maximum).Maximum, 2)
        } else { 0.0 }

        $peakDisk = if ($group.DiskSamples.Count -gt 0) {
            [math]::Round(($group.DiskSamples | Measure-Object -Maximum).Maximum, 2)
        } else { 0.0 }

        $result = [pscustomobject]@{
            Period        = $key
            PeriodStart   = $group.PeriodStart
            PeriodEnd     = $group.PeriodEnd
            AvgCPU        = $avgCPU
            AvgMemoryGB   = $avgMemory
            AvgDiskGB     = $avgDisk
            PeakCPU       = $peakCPU
            PeakMemoryGB  = $peakMemory
            PeakDiskGB    = $peakDisk
            VMCount       = $group.CPUSamples.Count
        }

        $results.Add($result)
    }

    return @($results)
}
