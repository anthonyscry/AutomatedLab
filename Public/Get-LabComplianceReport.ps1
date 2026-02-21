function Get-LabComplianceReport {
    <#
    .SYNOPSIS
        Generates a STIG compliance report for the lab.

    .DESCRIPTION
        Get-LabComplianceReport reads the STIG compliance cache and generates
        a comprehensive compliance report. Reports include pass/fail summary,
        compliance rate calculation, and per-VM status details. Supports
        multiple output formats including console, HTML, CSV, and JSON.

    .PARAMETER Format
        Output format: 'Console', 'Html', 'Csv', 'Json'. Defaults to the
        ReportFormats setting from Get-LabReportsConfig.

    .PARAMETER LabName
        Name of the lab for the report header. Defaults to reading from
        $GlobalLabConfig.Lab.LabName.

    .PARAMETER OutputPath
        Path to save the report file. Required for Html, Csv, Json formats.
        For Console format, this parameter is ignored.

    .PARAMETER ThresholdPercent
        Compliance threshold percentage for warnings. Defaults to the
        ComplianceThresholdPercent setting from Get-LabReportsConfig.

    .PARAMETER IncludeDetails
        Include detailed rule-level information. Not yet implemented.

    .PARAMETER CachePath
        Override path to the STIG compliance cache file. Defaults to the
        ComplianceCachePath setting from Get-LabSTIGConfig.

    .EXAMPLE
        Get-LabComplianceReport
        Displays a console compliance report with default settings.

    .EXAMPLE
        Get-LabComplianceReport -Format Html -OutputPath 'compliance.html'
        Generates an HTML compliance report.

    .EXAMPLE
        Get-LabComplianceReport -Format Csv -OutputPath 'compliance.csv'
        Exports compliance data to CSV for Excel analysis.

    .OUTPUTS
        For Console format: Console output (no return value)
        For Html/Csv/Json format: Path to saved report file
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Console', 'Html', 'Csv', 'Json')]
        [string]$Format,

        [string]$LabName,

        [string]$OutputPath,

        [int]$ThresholdPercent,

        [switch]$IncludeDetails,

        [string]$CachePath
    )

    $reportsConfig = Get-LabReportsConfig

    if (-not $PSBoundParameters.ContainsKey('Format')) {
        $Format = if ($reportsConfig.ReportFormats.Count -gt 0) {
            $reportsConfig.ReportFormats[0]
        } else {
            'Console'
        }
    }

    if (-not $PSBoundParameters.ContainsKey('LabName')) {
        $LabName = if (Test-Path variable:GlobalLabConfig -and $GlobalLabConfig.ContainsKey('Lab') -and $GlobalLabConfig.Lab.ContainsKey('LabName')) {
            $GlobalLabConfig.Lab.LabName
        } else {
            'AutomatedLab'
        }
    }

    if (-not $PSBoundParameters.ContainsKey('ThresholdPercent')) {
        $ThresholdPercent = $reportsConfig.ComplianceThresholdPercent
    }

    $complianceData = Get-LabSTIGCompliance -CachePath $CachePath

    if ($complianceData.Count -eq 0) {
        Write-Warning "No STIG compliance data found. Run Invoke-LabSTIGBaseline to generate compliance data."
        return $null
    }

    $formatParams = @{
        ComplianceData    = $complianceData
        Format            = $Format
        LabName           = $LabName
        ThresholdPercent  = $ThresholdPercent
        IncludeDetails    = $IncludeDetails
    }

    if ($Format -ne 'Console') {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $dateStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $extension = switch ($Format) {
                'Html' { '.html' }
                'Csv'  { '.csv' }
                'Json' { '.json' }
            }
            $OutputPath = Join-Path $reportsConfig.ComplianceReportPath "compliance-$dateStamp$extension"
        }
        $formatParams.OutputPath = $OutputPath
    }

    return Format-LabComplianceReport @formatParams
}
