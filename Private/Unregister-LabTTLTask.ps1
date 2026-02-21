function Unregister-LabTTLTask {
    <#
    .SYNOPSIS
        Removes the TTL monitoring scheduled task.

    .DESCRIPTION
        Unregisters the OpenCodeLab-TTLMonitor scheduled task. Idempotent:
        returns gracefully if the task does not exist. Called during lab
        teardown (Reset-Lab) to prevent orphaned tasks.

    .OUTPUTS
        PSCustomObject with TaskRemoved, TaskName, Message fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $taskName = 'OpenCodeLab-TTLMonitor'

    try {
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            return [pscustomobject]@{
                TaskRemoved = $true
                TaskName    = $taskName
                Message     = "Scheduled task '$taskName' removed"
            }
        }
        else {
            return [pscustomobject]@{
                TaskRemoved = $false
                TaskName    = $taskName
                Message     = "Scheduled task '$taskName' not found (already clean)"
            }
        }
    }
    catch {
        Write-Warning "[TTLTask] Unregister failed: $($_.Exception.Message)"
        return [pscustomobject]@{
            TaskRemoved = $false
            TaskName    = $taskName
            Message     = "Unregister failed: $($_.Exception.Message)"
        }
    }
}
