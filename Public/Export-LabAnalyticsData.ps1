function Export-LabAnalyticsData {
    <#
    .SYNOPSIS
        Exports lab analytics data to CSV or JSON file.

    .DESCRIPTION
        Export-LabAnalyticsData reads analytics events and exports them to a
        specified file in CSV or JSON format. Supports filtering by date range,
        event type, and lab name. CSV format exports flattened properties
        suitable for spreadsheet analysis. JSON format exports complete event
        objects with nested metadata.

    .PARAMETER OutputPath
        Path where export file will be written. Extension determines format:
        .csv for CSV, .json for JSON.

    .PARAMETER EventType
        Filter to events of this type only (optional).

    .PARAMETER LabName
        Filter to events for this lab only (optional).

    .PARAMETER After
        Only include events after this DateTime (optional).

    .PARAMETER Before
        Only include events before this DateTime (optional).

    .PARAMETER Force
        Overwrite existing file without prompting (default: prompt).

    .EXAMPLE
        Export-LabAnalyticsData -OutputPath 'analytics.csv'
        Exports all analytics events to CSV.

    .EXAMPLE
        Export-LabAnalyticsData -OutputPath 'feb-data.json' -After (Get-Date '2026-02-01') -Before (Get-Date '2026-03-01')
        Exports February 2026 events to JSON.

    .EXAMPLE
        Export-LabAnalyticsData -OutputPath 'deploys.csv' -EventType 'LabDeployed' -Force
        Exports only LabDeployed events to CSV, overwriting if exists.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$EventType,

        [string]$LabName,

        [DateTime]$After,

        [DateTime]$Before,

        [switch]$Force
    )

    $getExtension = [System.IO.Path]::GetExtension($OutputPath)
    $format = switch ($getExtension) {
        '.csv'  { 'CSV' }
        '.json' { 'JSON' }
        default { throw "Output file must have .csv or .json extension" }
    }

    $getAnalyticsParams = @{}

    if ($PSBoundParameters.ContainsKey('EventType')) {
        $getAnalyticsParams.EventType = $EventType
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

    $events = Get-LabAnalytics @getAnalyticsParams

    if ($events.Count -eq 0) {
        Write-Warning "No analytics events found matching the specified criteria"
        return $null
    }

    $shouldProcess = $Force -or $PSCmdlet.ShouldProcess(
        $OutputPath,
        "Export $($events.Count) analytics events to $format format"
    )

    if (-not $shouldProcess) {
        return $null
    }

    try {
        $parentDir = Split-Path -Parent $OutputPath
        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
            $null = New-Item -Path $parentDir -ItemType Directory -Force
            Write-Verbose "Created directory: $parentDir"
        }

        switch ($format) {
            'CSV' {
                $flatEvents = $events | ForEach-Object {
                    $metadataStr = if ($_.Metadata) {
                        ($_.Metadata.GetEnumerator() | ForEach-Object {
                            "$($_.Key)=$($_.Value)"
                        }) -join '; '
                    } else {
                        ''
                    }

                    [pscustomobject]@{
                        Timestamp   = $_.Timestamp
                        EventType   = $_.EventType
                        LabName     = $_.LabName
                        VMNames     = $_.VMNames -join ', '
                        Metadata    = $metadataStr
                        Host        = $_.Host
                        User        = $_.User
                    }
                }

                $flatEvents | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }

            'JSON' {
                $events | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
            }
        }

        $resolvedPath = (Resolve-Path $OutputPath).Path
        Write-Host "`n  Exported $($events.Count) events to: $resolvedPath" -ForegroundColor DarkGray
        return $resolvedPath
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Export-LabAnalyticsData: failed to export to '$OutputPath' - $_", $_.Exception),
                'Export-LabAnalyticsData.Failure',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $null
            )
        )
        return $null
    }
}
