function Register-LabTTLTask {
    <#
    .SYNOPSIS
        Registers the TTL monitoring scheduled task.

    .DESCRIPTION
        Creates a Windows Scheduled Task named OpenCodeLab-TTLMonitor that runs
        Invoke-LabTTLMonitor every 5 minutes under SYSTEM context. Idempotent:
        unregisters existing task first to prevent duplicate errors.

    .PARAMETER ProjectRoot
        Absolute path to the project root. Baked into the scheduled task command
        so SYSTEM context can find Lab-Common.ps1.

    .OUTPUTS
        PSCustomObject with TaskRegistered, TaskName, Message fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
    )

    $taskName = 'OpenCodeLab-TTLMonitor'

    try {
        # Idempotent: remove existing first
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        # Build the monitor invocation command
        # Bake absolute path at registration time so SYSTEM context finds it
        $labCommonPath = Join-Path $ProjectRoot 'Lab-Common.ps1'
        $command = ". '$labCommonPath'; Invoke-LabTTLMonitor"

        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes 5) `
            -RepetitionDuration ([TimeSpan]::MaxValue)

        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$command`""

        $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' `
            -LogonType ServiceAccount -RunLevel Highest

        $null = Register-ScheduledTask -TaskName $taskName -Trigger $trigger `
            -Action $action -Principal $principal `
            -Description 'OpenCodeLab TTL Monitor -- auto-suspends lab VMs when TTL expires'

        return [pscustomobject]@{
            TaskRegistered = $true
            TaskName       = $taskName
            Message        = "Scheduled task '$taskName' registered successfully"
        }
    }
    catch {
        Write-Warning "[TTLTask] Registration failed: $($_.Exception.Message)"
        return [pscustomobject]@{
            TaskRegistered = $false
            TaskName       = $taskName
            Message        = "Registration failed: $($_.Exception.Message)"
        }
    }
}
