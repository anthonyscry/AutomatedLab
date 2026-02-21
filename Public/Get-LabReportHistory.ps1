function Get-LabReportHistory {
    <#
    .SYNOPSIS
        Retrieves report generation history from analytics log.

    .DESCRIPTION
        Get-LabReportHistory reads analytics events and returns report generation
        history filtered by report type, format, date range, and scheduled flag.
        Provides audit trail for compliance auditing and operational review.

    .PARAMETER ReportType
        Filter to specific report type: 'Compliance', 'Resource', or 'All' (default).

    .PARAMETER Format
        Filter to specific output format: 'Console', 'Html', 'Csv', 'Json' (optional).

    .PARAMETER LabName
        Filter to events for this lab only (optional).

    .PARAMETER Scheduled
        Filter to scheduled reports only (switch).

    .PARAMETER After
        Only include reports generated after this DateTime (optional).

    .PARAMETER Before
        Only include reports generated before this DateTime (optional).

    .PARAMETER Last
        Return only the last N report events (optional, default 50).

    .EXAMPLE
        Get-LabReportHistory
        Returns all report generation events, last 50.

    .EXAMPLE
        Get-LabReportHistory -ReportType Compliance
        Returns only compliance report generation events.

    .OUTPUTS
        [pscustomobject[]] Report history entries with Timestamp, EventType, LabName,
        VMNames, Metadata (Format, OutputPath, Scheduled, summary statistics).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [ValidateSet('Compliance', 'Resource', 'All')]
        [string]$ReportType = 'All',

        [ValidateSet('Console', 'Html', 'Csv', 'Json')]
        [string]$Format,

        [string]$LabName,

        [switch]$Scheduled,

        [DateTime]$After,

        [DateTime]$Before,

        [int]$Last = 50
    )

    $getAnalyticsParams = @{
        Last = $Last
    }

    if ($PSBoundParameters.ContainsKey('LabName')) {
        $getAnalyticsParams.LabName = $LabName
    }

    if ($PSBoundParameters.ContainsKey('After')) {
        $getAnalyticsParams.After = $After
    }

    if ($PSBoundParameters.ContainsKey('Before')) {
        $getAnalyticsParams.Before = $Before
    }

    $allEvents = Get-LabAnalytics @getAnalyticsParams

    $reportEvents = if ($ReportType -eq 'All') {
        @($allEvents | Where-Object { $_.EventType -match '^Report(Compliance|Resource)$' })
    } else {
        @($allEvents | Where-Object { $_.EventType -eq "Report$ReportType" })
    }

    if ($PSBoundParameters.ContainsKey('Format')) {
        $reportEvents = @($reportEvents | Where-Object { $_.Metadata.Format -eq $Format })
    }

    if ($Scheduled.IsPresent) {
        $reportEvents = @($reportEvents | Where-Object { $_.Metadata.Scheduled -eq $true })
    }

    $enriched = @($reportEvents | ForEach-Object {
        $summary = @{}
        foreach ($key in $_.Metadata.Keys) {
            if ($key -notin @('Format', 'OutputPath', 'Scheduled', 'ReportType')) {
                $summary[$key] = $_.Metadata[$key]
            }
        }

        [pscustomobject]@{
            GeneratedAt    = $_.Timestamp
            ReportType     = if ($_.EventType -match '^Report(\w+)$') { $matches[1] } else { 'Unknown' }
            Format         = $_.Metadata.Format
            LabName        = $_.LabName
            OutputPath     = $_.Metadata.OutputPath
            Scheduled      = $_.Metadata.Scheduled
            Summary        = if ($summary.Count -gt 0) { [pscustomobject]$summary } else { $null }
            Host           = $_.Host
            User           = $_.User
        }
    })

    return @($enriched | Sort-Object -Property GeneratedAt -Descending)
}
