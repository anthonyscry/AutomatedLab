# Invoke-LabSetup.ps1
# Runs preflight check and bootstrap sequence.
# Used by the 'setup' action (no health check or VM validation).

function Invoke-LabSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$EffectiveMode,

        [Parameter(Mandatory)]
        [string]$ScriptDir,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [switch]$NonInteractive,
        [switch]$AutoFixSubnetConflict
    )

    try {
        $preflightArgs = Get-LabPreflightArgs
        $bootstrapArgs = Get-LabBootstrapArgs -Mode $EffectiveMode -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict

        Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        Invoke-LabRepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
    }
    catch {
        throw "Invoke-LabSetup: setup failed during script execution - $_"
    }
}
