function Invoke-ScheduledReport {
    <#
    .SYNOPSIS
        Executes a scheduled report generation.

    .DESCRIPTION
        Invoke-ScheduledReport is called by Windows Scheduled Tasks to generate
        reports on a schedule. It imports the SimpleLab module, runs the specified
        report type, and saves the output to the scheduled reports directory.
        Errors are logged but do not throw to prevent task failures.

    .PARAMETER ReportType
        Type of report to generate: 'Compliance' or 'Resource'.

    .PARAMETER OutputPath
        Directory where the report file will be saved.

    .PARAMETER LabName
        Name of the lab for the report header.

    .PARAMETER Format
        Output format for the report (default: 'Html').

    .EXAMPLE
        Invoke-ScheduledReport -ReportType Compliance -OutputPath '.planning/reports/scheduled'
        Generates a compliance HTML report in the scheduled reports directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Compliance', 'Resource')]
        [string]$ReportType,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$LabName = 'AutomatedLab',

        [ValidateSet('Console', 'Html', 'Csv', 'Json')]
        [string]$Format = 'Html'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] ScheduledReport: $ReportType report requested"

    try {
        $modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'SimpleLab.psm1'

        if (-not (Test-Path $modulePath)) {
            throw "Module not found at '$modulePath'"
        }

        Import-Module $modulePath -Force

        $dateStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $extension = switch ($Format) {
            'Html' { '.html' }
            'Csv'  { '.csv' }
            'Json' { '.json' }
        }

        $fileName = "$ReportType-$dateStamp$extension"
        $fullOutputPath = Join-Path $OutputPath $fileName

        $null = New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction SilentlyContinue

        switch ($ReportType) {
            'Compliance' {
                $null = Get-LabComplianceReport -Format $Format -LabName $LabName -OutputPath $fullOutputPath
            }
            'Resource' {
                $null = Get-LabResourceReport -Format $Format -LabName $LabName -OutputPath $fullOutputPath
            }
        }

        if (Test-Path $fullOutputPath) {
            Write-Host "Scheduled $ReportType report generated: $fullOutputPath"
        } else {
            Write-Warning "Scheduled $ReportType report may have failed - output file not found"
        }
    }
    catch {
        Write-Error "Invoke-ScheduledReport failed for $ReportType report: $($_.Exception.Message)"
    }
}
