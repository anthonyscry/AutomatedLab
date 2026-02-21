function Get-LabReportScheduleConfig {
    <#
    .SYNOPSIS
        Reads report schedule configuration from global lab config.

    .DESCRIPTION
        Get-LabReportScheduleConfig returns a ReportSchedule configuration object
        with safe defaults when keys are missing from $GlobalLabConfig. Contains
        ContainsKey guards for all nested keys to prevent errors under StrictMode.

    .OUTPUTS
        [pscustomobject] with Enabled, TaskPrefix, OutputBasePath properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $config = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }

    $enabled = if ($null -ne $config -and $config.ContainsKey('ReportSchedule') -and $config.ReportSchedule.ContainsKey('Enabled')) {
        [bool]$config.ReportSchedule.Enabled
    } else {
        $true
    }

    $taskPrefix = if ($null -ne $config -and $config.ContainsKey('ReportSchedule') -and $config.ReportSchedule.ContainsKey('TaskPrefix')) {
        [string]$config.ReportSchedule.TaskPrefix
    } else {
        'AutomatedLabReport'
    }

    $outputBasePath = if ($null -ne $config -and $config.ContainsKey('ReportSchedule') -and $config.ReportSchedule.ContainsKey('OutputBasePath')) {
        [string]$config.ReportSchedule.OutputBasePath
    } else {
        '.planning/reports/scheduled'
    }

    return [pscustomobject]@{
        Enabled         = $enabled
        TaskPrefix      = $taskPrefix
        OutputBasePath  = $outputBasePath
    }
}
