function Get-LabDashboardConfig {
    <#
    .SYNOPSIS
        Reads Dashboard configuration from GlobalLabConfig with safe defaults.

    .DESCRIPTION
        Returns a PSCustomObject with Dashboard threshold settings. Uses ContainsKey guards on
        every read to prevent StrictMode failures when keys are absent.
        Returns safe defaults when the Dashboard block or individual keys are missing.

    .OUTPUTS
        PSCustomObject with SnapshotStaleDays, SnapshotStaleCritical, DiskUsagePercent,
        DiskUsageCritical, UptimeStaleHours fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $dashBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('Dashboard')) { $GlobalLabConfig.Dashboard } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        SnapshotStaleDays  = if ($dashBlock.ContainsKey('SnapshotStaleDays'))  { [int]$dashBlock.SnapshotStaleDays }     else { 7 }
        SnapshotStaleCritical = if ($dashBlock.ContainsKey('SnapshotStaleCritical')) { [int]$dashBlock.SnapshotStaleCritical } else { 30 }
        DiskUsagePercent   = if ($dashBlock.ContainsKey('DiskUsagePercent'))   { [int]$dashBlock.DiskUsagePercent }    else { 80 }
        DiskUsageCritical  = if ($dashBlock.ContainsKey('DiskUsageCritical'))  { [int]$dashBlock.DiskUsageCritical }   else { 95 }
        UptimeStaleHours   = if ($dashBlock.ContainsKey('UptimeStaleHours'))   { [int]$dashBlock.UptimeStaleHours }    else { 72 }
    }
}
