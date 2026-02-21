function Get-LabAnalytics {
    <#
    .SYNOPSIS
        Retrieves lab analytics events from the analytics log.

    .DESCRIPTION
        Get-LabAnalytics reads analytics events from the analytics JSON file and
        returns either all events or filtered events by type, date range, or lab name.
        Events are sorted by timestamp descending (newest first).

    .PARAMETER EventType
        Filter to events of this type only (optional).

    .PARAMETER LabName
        Filter to events for this lab only (optional).

    .PARAMETER After
        Only include events after this DateTime (optional).

    .PARAMETER Before
        Only include events before this DateTime (optional).

    .PARAMETER Last
        Return only the last N events (optional, default 100).

    .EXAMPLE
        Get-LabAnalytics
        Returns all analytics events, newest 100.

    .EXAMPLE
        Get-LabAnalytics -EventType 'LabDeployed'
        Returns only LabDeployed events.

    .EXAMPLE
        Get-LabAnalytics -LabName 'AutomatedLab' -Last 10
        Returns last 10 events for AutomatedLab.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$EventType,

        [string]$LabName,

        [DateTime]$After,

        [DateTime]$Before,

        [int]$Last = 100
    )

    $analyticsConfig = Get-LabAnalyticsConfig
    $storagePath = $analyticsConfig.StoragePath

    if (-not (Test-Path $storagePath)) {
        Write-Warning "Analytics file not found at '$storagePath'"
        return @()
    }

    try {
        $data = Get-Content -Raw -Path $storagePath | ConvertFrom-Json
        $events = if ($data.events) { @($data.events) } else { @() }
    }
    catch {
        Write-Warning "Failed to read analytics file '$storagePath': $($_.Exception.Message)"
        return @()
    }

    $filtered = $events

    if ($PSBoundParameters.ContainsKey('EventType')) {
        $filtered = @($filtered | Where-Object { $_.EventType -eq $EventType })
    }

    if ($PSBoundParameters.ContainsKey('LabName')) {
        $filtered = @($filtered | Where-Object { $_.LabName -eq $LabName })
    }

    if ($PSBoundParameters.ContainsKey('After')) {
        $filtered = @($filtered | Where-Object { [DateTime]::Parse($_.Timestamp) -gt $After })
    }

    if ($PSBoundParameters.ContainsKey('Before')) {
        $filtered = @($filtered | Where-Object { [DateTime]::Parse($_.Timestamp) -lt $Before })
    }

    $sorted = @($filtered | Sort-Object -Property @{ Expression = { [DateTime]::Parse($_.Timestamp) }; Descending = $true })

    return @($sorted | Select-Object -First $Last)
}
