# Invoke-LabOneButtonReset.ps1
# Full one-button lab reset: tears down existing lab then runs one-button setup.
# Supports dry-run mode, configurable network removal, and bypass prompt.

function Invoke-LabOneButtonReset {
    [CmdletBinding()]
    param(
        [switch]$DropNetwork,
        [switch]$DryRun,
        [switch]$Force,
        [switch]$NonInteractive,
        [switch]$AutoFixSubnetConflict,

        [Parameter(Mandatory)]
        [hashtable]$LabConfig,

        [Parameter(Mandatory)]
        [string]$ScriptDir,

        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter(Mandatory)]
        [string]$LabName,

        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$EffectiveMode,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents
    )

    try {
        Write-Host "`n=== ONE-BUTTON RESET/REBUILD ===" -ForegroundColor Red
        if ($DryRun) {
            Write-Host "  Dry run enabled: reset/rebuild actions will not execute." -ForegroundColor Yellow
            Invoke-LabBlowAway -BypassPrompt -DropNetwork:$DropNetwork -Simulate -LabConfig $LabConfig -SwitchName $SwitchName -RunEvents $RunEvents
            Add-LabRunEvent -Step 'one-button-reset' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
            return
        }

        # For direct action calls (not from menu), require confirmation unless Force/NonInteractive
        $shouldBypassPrompt = $Force -or $NonInteractive
        Invoke-LabBlowAway -BypassPrompt:$shouldBypassPrompt -DropNetwork:$DropNetwork -LabConfig $LabConfig -SwitchName $SwitchName -RunEvents $RunEvents
        Invoke-LabOneButtonSetup -EffectiveMode $EffectiveMode -LabConfig $LabConfig -ScriptDir $ScriptDir -LabName $LabName -RunEvents $RunEvents -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Invoke-LabOneButtonReset: reset operation failed - $_", $_.Exception),
                'Invoke-LabOneButtonReset.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}
