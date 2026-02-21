function Remove-LabReportSchedule {
    <#
    .SYNOPSIS
        Removes a scheduled report task.

    .DESCRIPTION
        Remove-LabReportSchedule unregisters a scheduled report task, stopping
        automatic report generation. Supports ShouldProcess for confirmation and
        -WhatIf for safe preview of the operation.

    .PARAMETER TaskName
        Name of the scheduled task to remove.

    .EXAMPLE
        Remove-LabReportSchedule -TaskName 'AutomatedLabReport_Compliance_daily'
        Removes the daily compliance report schedule.

    .EXAMPLE
        Get-LabReportSchedule | Remove-LabReportSchedule
        Removes all report scheduled tasks (with confirmation).

    .OUTPUTS
        [bool] True if task was removed, false otherwise.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$TaskName
    )

    begin {
        $removedCount = 0
    }

    process {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

        if ($null -eq $task) {
            Write-Warning "Scheduled task '$TaskName' not found"
            return $false
        }

        if ($PSCmdlet.ShouldProcess($TaskName, 'Remove scheduled report task')) {
            try {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
                Write-Host "`n  Removed scheduled task: $TaskName" -ForegroundColor Green
                $removedCount++
                return $true
            }
            catch {
                $PSCmdlet.WriteError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Failed to remove scheduled task '$TaskName' - $_", $_.Exception),
                        'Remove-LabReportSchedule.Failure',
                        [System.Management.Automation.ErrorCategory]::FromStdErr,
                        $null
                    )
                )
                return $false
            }
        }

        return $false
    }

    end {
        if ($removedCount -gt 1) {
            Write-Host "`n  Removed $removedCount scheduled report tasks." -ForegroundColor Green
        }
    }
}
