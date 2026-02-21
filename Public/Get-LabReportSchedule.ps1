function Get-LabReportSchedule {
    <#
    .SYNOPSIS
        Lists scheduled report tasks.

    .DESCRIPTION
        Get-LabReportSchedule retrieves all AutomatedLab report scheduled tasks
        and displays their configuration including report type, frequency, and
        next run time. Returns scheduled task objects for further processing.

    .PARAMETER TaskName
        Specific task name to retrieve (optional). If not specified, returns all
        report scheduled tasks.

    .EXAMPLE
        Get-LabReportSchedule
        Lists all report scheduled tasks.

    .EXAMPLE
        Get-LabReportSchedule -TaskName 'AutomatedLabReport_Compliance_daily'
        Returns details for the specific compliance daily task.

    .OUTPUTS
        [Microsoft.Management.Infrastructure.CimInstance[]] Scheduled task objects.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance[]])]
    param(
        [string]$TaskName
    )

    $scheduleConfig = Get-LabReportScheduleConfig
    $taskPrefix = $scheduleConfig.TaskPrefix

    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue

    if ($null -eq $allTasks) {
        Write-Host "`n  No report scheduled tasks found." -ForegroundColor Yellow
        return @()
    }

    $reportTasks = if ($PSBoundParameters.ContainsKey('TaskName')) {
        @($allTasks | Where-Object { $_.TaskName -eq $TaskName })
    } else {
        @($allTasks | Where-Object { $_.TaskName -like "$taskPrefix*" })
    }

    if ($reportTasks.Count -eq 0) {
        Write-Host "`n  No report scheduled tasks found." -ForegroundColor Yellow
        return @()
    }

    Write-Host "`n  Report Scheduled Tasks:" -ForegroundColor Cyan
    Write-Host '  ----------------------' -ForegroundColor Cyan

    foreach ($task in $reportTasks) {
        $nextRun = if ($task.Triggers) {
            $task.Triggers[0].StartBoundary
        } else {
            'Unknown'
        }

        $frequency = if ($task.Triggers -and $task.Triggers[0].Daily) {
            'Daily'
        } elseif ($task.Triggers -and $task.Triggers[0].Weekly) {
            'Weekly'
        } else {
            'Unknown'
        }

        $reportType = if ($task.TaskName -match '_(Compliance|Resource)_') {
            $matches[1]
        } else {
            'Unknown'
        }

        Write-Host "`n  Task Name:    $($task.TaskName)" -ForegroundColor White
        Write-Host "  Report Type:  $reportType" -ForegroundColor DarkGray
        Write-Host "  Frequency:    $frequency" -ForegroundColor DarkGray
        Write-Host "  Next Run:     $nextRun" -ForegroundColor DarkGray
        Write-Host "  State:        $($task.State)" -ForegroundColor DarkGray
    }

    Write-Host ''

    return $reportTasks
}
