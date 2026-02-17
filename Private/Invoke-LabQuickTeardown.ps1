# Invoke-LabQuickTeardown.ps1
# Performs a quick teardown: stops VMs and optionally restores LabReady snapshot.
# Supports dry-run mode to preview without executing.

function Invoke-LabQuickTeardown {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [Parameter(Mandatory)][string]$LabName,
        [Parameter(Mandatory)][string[]]$CoreVMNames,
        [Parameter(Mandatory)][hashtable]$LabConfig,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    if ($DryRun) {
        Write-Host "`n=== DRY RUN: QUICK TEARDOWN ===" -ForegroundColor Yellow
        Write-Host '  Would stop VMs and restore LabReady snapshot when available' -ForegroundColor DarkGray
        Add-LabRunEvent -Step 'teardown-quick' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
        return
    }

    Write-Host "`n=== QUICK TEARDOWN ===" -ForegroundColor Cyan
    Add-LabRunEvent -Step 'teardown-quick' -Status 'start' -Message 'stop + optional restore' -RunEvents $RunEvents
    Stop-LabVMsSafe -LabName $LabName -CoreVMNames $CoreVMNames

    try {
        if (Test-LabReadySnapshot -LabName $LabName -VMNames (Get-LabExpectedVMs -LabConfig $LabConfig) -CoreVMNames $CoreVMNames) {
            Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
            Add-LabRunEvent -Step 'teardown-quick' -Status 'ok' -Message 'LabReady restored' -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message 'Quick teardown complete (LabReady restored)' -Indent 0
        }
        else {
            Add-LabRunEvent -Step 'teardown-quick' -Status 'warn' -Message 'LabReady not found; VMs stopped only' -RunEvents $RunEvents
            Write-LabStatus -Status WARN -Message 'LabReady snapshot missing; quick teardown stopped VMs only.' -Indent 0
        }
    }
    catch {
        Add-LabRunEvent -Step 'teardown-quick' -Status 'fail' -Message 'Restore skipped after stop' -RunEvents $RunEvents
        Write-LabStatus -Status WARN -Message "Quick teardown restored no snapshot: $($_.Exception.Message)" -Indent 0
    }
}
