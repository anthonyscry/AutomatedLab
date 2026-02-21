function Get-LabResourceReport {
    <#
    .SYNOPSIS
        Generates a resource utilization report for the lab.

    .DESCRIPTION
        Get-LabResourceReport collects current VM metrics and generates
        a comprehensive resource utilization report. Reports include summary
        statistics, bottleneck identification, and per-VM resource details.
        Supports multiple output formats including console, HTML, CSV, and JSON.
        Can optionally include trend analysis over time periods.

    .PARAMETER Format
        Output format: 'Console', 'Html', 'Csv', 'Json'. Defaults to 'Console'.

    .PARAMETER LabName
        Name of the lab for the report header. Defaults to reading from
        $GlobalLabConfig.Lab.LabName.

    .PARAMETER OutputPath
        Path to save the report file. Required for Html, Csv, Json formats.
        For Console format, this parameter is ignored.

    .PARAMETER IncludeTrends
        Include trend analysis in the report (JSON format only).

    .PARAMETER TrendPeriod
        Time period for trend grouping: 'Hour', 'Day', 'Week'. Defaults to 'Day'.

    .PARAMETER Thresholds
        Hashtable with custom warning thresholds for CPU, Memory, Disk.

    .EXAMPLE
        Get-LabResourceReport
        Displays a console resource report with default settings.

    .EXAMPLE
        Get-LabResourceReport -Format Html -OutputPath 'resources.html'
        Generates an HTML resource report.

    .EXAMPLE
        Get-LabResourceReport -IncludeTrends -TrendPeriod Week -OutputPath 'resources.json'
        Generates a JSON report with weekly trend analysis.

    .OUTPUTS
        For Console format: Console output (no return value)
        For Html/Csv/Json format: Path to saved report file
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Console', 'Html', 'Csv', 'Json')]
        [string]$Format = 'Console',

        [string]$LabName,

        [string]$OutputPath,

        [switch]$IncludeTrends,

        [ValidateSet('Hour', 'Day', 'Week')]
        [string]$TrendPeriod = 'Day',

        [hashtable]$Thresholds
    )

    if (-not $PSBoundParameters.ContainsKey('LabName')) {
        $LabName = if (Test-Path variable:GlobalLabConfig -and $GlobalLabConfig.ContainsKey('Lab') -and $GlobalLabConfig.Lab.ContainsKey('LabName')) {
            $GlobalLabConfig.Lab.LabName
        } else {
            'AutomatedLab'
        }
    }

    try {
        $vmMetrics = Get-LabVMMetrics
    }
    catch {
        Write-Warning "Failed to collect VM metrics: $($_.Exception.Message)"
        $vmMetrics = @()
    }

    if ($vmMetrics.Count -eq 0) {
        Write-Warning "No VM metrics found. Ensure lab VMs are running."
        return $null
    }

    # Convert VM metrics to resource data format expected by Format-LabResourceReport
    $resourceData = @($vmMetrics | ForEach-Object {
        $cpu = if ($_.CPU) { $_.CPU } else { 0 }
        $mem = if ($_.MemoryGB) { $_.MemoryGB } elseif ($_.Memory) { $_.Memory / 1024 } else { 0 }
        $disk = if ($_.DiskUsagePercent) { $_.DiskUsagePercent }
                elseif ($_.DiskGB) { $_.DiskGB }
                elseif ($_.DiskUsageGB) { $_.DiskUsageGB }
                else { 0 }

        [pscustomobject]@{
            VMName          = $_.VMName
            CPUPercent      = $cpu
            MemoryGB        = $mem
            DiskGB          = $disk
            CollectedAt     = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
        }
    })

    $trendData = @()
    if ($IncludeTrends -and $Format -eq 'Json') {
        try {
            $analyticsEvents = Get-LabAnalytics
            $trendData = Get-LabResourceTrendCore -VMMetrics $resourceData -AnalyticsEvents $analyticsEvents -Period $TrendPeriod
        }
        catch {
            Write-Warning "Failed to generate trend data: $($_.Exception.Message)"
        }
    }

    $formatParams = @{
        ResourceData = $resourceData
        Format       = $Format
        LabName      = $LabName
    }

    if ($Format -ne 'Console') {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $reportsConfig = Get-LabReportsConfig
            $dateStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $extension = switch ($Format) {
                'Html' { '.html' }
                'Csv'  { '.csv' }
                'Json' { '.json' }
            }
            $reportDir = Join-Path (Split-Path $reportsConfig.ComplianceReportPath -Parent) 'resources'
            $OutputPath = Join-Path $reportDir "resources-$dateStamp$extension"
        }
        $formatParams.OutputPath = $OutputPath
    }

    if ($PSBoundParameters.ContainsKey('Thresholds')) {
        $formatParams.Thresholds = $Thresholds
    }

    if ($IncludeTrends -and $trendData.Count -gt 0) {
        $formatParams.TrendData = $trendData
    }

    return Format-LabResourceReport @formatParams
}
