function Get-LabReportsConfig {
    <#
    .SYNOPSIS
        Reads reports configuration from global lab config.

    .DESCRIPTION
        Get-LabReportsConfig returns a Reports configuration object with safe
        defaults when keys are missing from $GlobalLabConfig. Contains ContainsKey
        guards for all nested keys to prevent errors under StrictMode.

    .OUTPUTS
        [pscustomobject] with ComplianceReportPath, IncludeDetailedResults,
        ComplianceThresholdPercent, ReportFormats properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $config = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }

    $complianceReportPath = if ($null -ne $config -and $config.ContainsKey('Reports') -and $config.Reports.ContainsKey('ComplianceReportPath')) {
        [string]$config.Reports.ComplianceReportPath
    } else {
        '.planning/reports/compliance'
    }

    $includeDetailedResults = if ($null -ne $config -and $config.ContainsKey('Reports') -and $config.Reports.ContainsKey('IncludeDetailedResults')) {
        [bool]$config.Reports.IncludeDetailedResults
    } else {
        $false
    }

    $complianceThresholdPercent = if ($null -ne $config -and $config.ContainsKey('Reports') -and $config.Reports.ContainsKey('ComplianceThresholdPercent')) {
        [int]$config.Reports.ComplianceThresholdPercent
    } else {
        80
    }

    $reportFormats = if ($null -ne $config -and $config.ContainsKey('Reports') -and $config.Reports.ContainsKey('ReportFormats')) {
        @([string[]]$config.Reports.ReportFormats)
    } else {
        @('Console', 'Html')
    }

    return [pscustomobject]@{
        ComplianceReportPath       = $complianceReportPath
        IncludeDetailedResults     = $includeDetailedResults
        ComplianceThresholdPercent = $complianceThresholdPercent
        ReportFormats              = $reportFormats
    }
}
