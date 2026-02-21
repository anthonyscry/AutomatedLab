function Schedule-LabReport {
    <#
    .SYNOPSIS
        Creates a scheduled task for automatic report generation.

    .DESCRIPTION
        Schedule-LabReport creates a Windows Scheduled Task that automatically
        generates compliance or resource reports on a daily or weekly schedule.
        Reports are saved to the scheduled reports directory. The task runs
        under the current user context and survives PowerShell session termination.

    .PARAMETER ReportType
        Type of report to generate: 'Compliance' or 'Resource'.

    .PARAMETER Frequency
        Schedule frequency: 'Daily' or 'Weekly'.

    .PARAMETER Time
        Time of day to run the report (default: '02:00').

    .PARAMETER DaysOfWeek
        Days of week for weekly schedules (default: 'Monday').

    .PARAMETER OutputPath
        Directory where scheduled reports are saved. Defaults to the
        OutputBasePath setting from Get-LabReportScheduleConfig.

    .PARAMETER LabName
        Name of the lab for the report header.

    .PARAMETER Format
        Output format for the report (default: 'Html').

    .EXAMPLE
        Schedule-LabReport -ReportType Compliance -Frequency Daily
        Creates a daily compliance report scheduled for 2:00 AM.

    .EXAMPLE
        Schedule-LabReport -ReportType Resource -Frequency Weekly -DaysOfWeek Monday, Friday
        Creates a weekly resource report scheduled for Monday and Friday at 2:00 AM.

    .OUTPUTS
        [string] Name of the created scheduled task.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Compliance', 'Resource')]
        [string]$ReportType,

        [Parameter(Mandatory)]
        [ValidateSet('Daily', 'Weekly')]
        [string]$Frequency,

        [string]$Time = '02:00',

        [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
        [string[]]$DaysOfWeek = @('Monday'),

        [string]$OutputPath,

        [string]$LabName,

        [ValidateSet('Html', 'Csv', 'Json')]
        [string]$Format = 'Html'
    )

    $scheduleConfig = Get-LabReportScheduleConfig

    if (-not $scheduleConfig.Enabled) {
        Write-Warning "Report scheduling is disabled. Enable it in Lab-Config.ps1 by setting ReportSchedule.Enabled = `$true"
        return $null
    }

    if (-not $PSBoundParameters.ContainsKey('LabName')) {
        $LabName = if (Test-Path variable:GlobalLabConfig -and $GlobalLabConfig.ContainsKey('Lab') -and $GlobalLabConfig.Lab.ContainsKey('LabName')) {
            $GlobalLabConfig.Lab.LabName
        } else {
            'AutomatedLab'
        }
    }

    if (-not $PSBoundParameters.ContainsKey('OutputPath')) {
        $OutputPath = $scheduleConfig.OutputBasePath
    }

    $taskName = '{0}_{1}_{2}' -f $scheduleConfig.TaskPrefix, $ReportType, $Frequency.ToLower()

    $timeSpan = [TimeSpan]::Parse($Time)

    $trigger = switch ($Frequency) {
        'Daily' {
            New-ScheduledTaskTrigger -Daily -At $timeSpan
        }
        'Weekly' {
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DaysOfWeek -At $timeSpan
        }
    }

    $modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'SimpleLab.psm1'
    $scriptPath = Join-Path (Join-Path $PSScriptRoot '..') Private 'Invoke-ScheduledReport.ps1'

    $actionScript = @"
Import-Module '$modulePath' -Force
& '$scriptPath' -ReportType '$ReportType' -OutputPath '$OutputPath' -LabName '$LabName' -Format '$Format'
"@

    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$actionScript`""

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

    if ($PSCmdlet.ShouldProcess($taskName, 'Create scheduled report task')) {
        try {
            # Remove existing task if present (idempotent)
            $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($existing) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            }

            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
            Write-Host "`n  Scheduled task created: $taskName" -ForegroundColor Green
            Write-Host "  Report Type:   $ReportType" -ForegroundColor DarkGray
            Write-Host "  Frequency:     $Frequency" -ForegroundColor DarkGray
            if ($Frequency -eq 'Weekly') {
                Write-Host "  Days:          $($DaysOfWeek -join ', ')" -ForegroundColor DarkGray
            }
            Write-Host "  Time:          $Time" -ForegroundColor DarkGray
            Write-Host "  Output Path:   $OutputPath" -ForegroundColor DarkGray

            return $taskName
        }
        catch {
            $PSCmdlet.WriteError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Failed to create scheduled task '$taskName' - $_", $_.Exception),
                    'Schedule-LabReport.Failure',
                    [System.Management.Automation.ErrorCategory]::FromStdErr,
                    $null
                )
            )
            return $null
        }
    }

    return $null
}
