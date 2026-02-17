# Invoke-LabOneButtonSetup.ps1
# Full one-button lab setup sequence: preflight -> bootstrap -> health check.
# Includes automatic rollback on health gate failure.

function Invoke-LabOneButtonSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$EffectiveMode,

        [Parameter(Mandatory)]
        [hashtable]$LabConfig,

        [Parameter(Mandatory)]
        [string]$ScriptDir,

        [Parameter(Mandatory)]
        [string]$LabName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [switch]$NonInteractive,
        [switch]$AutoFixSubnetConflict
    )

    Write-Host "`n=== ONE-BUTTON SETUP ===" -ForegroundColor Cyan
    Write-Host "  Mode: WINDOWS CORE (DC1 + SVR1 + WS1)" -ForegroundColor Green
    Write-Host "  Bootstrapping prerequisites + deploying lab + start + status" -ForegroundColor Gray

    $preflightArgs = Get-LabPreflightArgs
    $bootstrapArgs = Get-LabBootstrapArgs -Mode $EffectiveMode -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict

    Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
    Invoke-LabRepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs -ScriptDir $ScriptDir -RunEvents $RunEvents

    # Verify expected VMs exist after bootstrap (bootstrap chains into deploy)
    $expectedVMs = Get-LabExpectedVMs -LabConfig $LabConfig
    $missingVMs = $expectedVMs | Where-Object { -not (Hyper-V\Get-VM -Name $_ -ErrorAction SilentlyContinue) }
    if ($missingVMs) {
        throw "VMs not found after bootstrap: $($missingVMs -join ', '). Deploy may have failed."
    }

    Invoke-LabRepoScript -BaseName 'Start-LabDay' -ScriptDir $ScriptDir -RunEvents $RunEvents
    Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents

    $healthArgs = Get-LabHealthArgs
    try {
        Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        Write-LabStatus -Status OK -Message "Post-deploy health gate passed"
    } catch {
        Write-LabStatus -Status FAIL -Message "Post-deploy health gate failed"
        Write-Host "  Attempting automatic rollback to LabReady..." -ForegroundColor Yellow
        try {
            if (-not (Test-LabReadySnapshot -LabName $LabName -CoreVMNames @($LabConfig.Lab.CoreVMNames))) {
                Add-LabRunEvent -Step 'rollback' -Status 'fail' -Message 'LabReady snapshot missing' -RunEvents $RunEvents
                Write-LabStatus -Status WARN -Message "LabReady snapshot missing. Cannot auto-rollback."
                Write-Host "  Run deploy once to recreate LabReady checkpoint." -ForegroundColor Yellow
            } else {
                Add-LabRunEvent -Step 'rollback' -Status 'start' -Message 'Restore-LabVMSnapshot LabReady' -RunEvents $RunEvents
                Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                Add-LabRunEvent -Step 'rollback' -Status 'ok' -Message 'LabReady restored' -RunEvents $RunEvents
                Write-LabStatus -Status OK -Message "Automatic rollback completed"
                Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents
            }
        } catch {
            Add-LabRunEvent -Step 'rollback' -Status 'fail' -Message $_.Exception.Message -RunEvents $RunEvents
            Write-LabStatus -Status WARN -Message "Automatic rollback failed: $($_.Exception.Message)"
        }
        throw
    }

    Write-Host ''
    Write-LabStatus -Status OK -Message 'One-button setup complete.'
}
