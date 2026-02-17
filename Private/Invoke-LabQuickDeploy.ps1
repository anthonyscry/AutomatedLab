# Invoke-LabQuickDeploy.ps1
# Performs a quick deploy sequence: Start-LabDay -> Lab-Status -> Test-OpenCodeLabHealth.
# Supports dry-run mode to preview without executing.

function Invoke-LabQuickDeploy {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    try {
        if ($DryRun) {
            Write-Host "`n=== DRY RUN: QUICK DEPLOY ===" -ForegroundColor Yellow
            Write-Host '  Would run quick startup sequence: Start-LabDay -> Lab-Status -> Test-OpenCodeLabHealth' -ForegroundColor DarkGray
            Add-LabRunEvent -Step 'deploy-quick' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
            return
        }

        Write-Host "`n=== QUICK DEPLOY ===" -ForegroundColor Cyan
        Invoke-LabRepoScript -BaseName 'Start-LabDay' -ScriptDir $ScriptDir -RunEvents $RunEvents
        Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents
        $healthArgs = Get-LabHealthArgs
        Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
    }
    catch {
        throw "Invoke-LabQuickDeploy: quick deploy failed - $_"
    }
}
