# Invoke-LabOrchestrationActionCore.ps1
# Central dispatch for deploy/teardown orchestration actions.
# Routes to quick or full path based on Intent and Mode.

function Invoke-LabOrchestrationActionCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('deploy', 'teardown')]
        [string]$OrchestrationAction,

        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$Mode,

        [Parameter(Mandatory)]
        [object]$Intent,

        [Parameter(Mandatory)]
        [hashtable]$LabConfig,

        [Parameter(Mandatory)]
        [string]$ScriptDir,

        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [switch]$Force,
        [switch]$NonInteractive,
        [switch]$RemoveNetwork,
        [switch]$DryRun,
        [switch]$AutoFixSubnetConflict,

        [Parameter()]
        [string]$Scenario
    )

    try {
        switch ($OrchestrationAction) {
            'deploy' {
                if ($Intent.RunQuickStartupSequence) {
                    Invoke-LabQuickDeploy -DryRun:$DryRun -ScriptDir $ScriptDir -RunEvents $RunEvents
                }
                else {
                    $deployArgs = Get-LabDeployArgs -Mode $Mode -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict
                    if (-not [string]::IsNullOrWhiteSpace($Scenario)) {
                        $deployArgs += @('-Scenario', $Scenario)
                    }
                    Invoke-LabRepoScript -BaseName 'Deploy' -Arguments $deployArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
                }
            }
            'teardown' {
                if ($Intent.RunQuickReset) {
                    Invoke-LabQuickTeardown -DryRun:$DryRun -LabName $LabConfig.Lab.Name -CoreVMNames @($LabConfig.Lab.CoreVMNames) -LabConfig $LabConfig -RunEvents $RunEvents
                }
                else {
                    Invoke-LabBlowAway -BypassPrompt:($Force -or $NonInteractive) -DropNetwork:$RemoveNetwork -Simulate:$DryRun -LabConfig $LabConfig -SwitchName $SwitchName -RunEvents $RunEvents
                }
            }
        }
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Invoke-LabOrchestrationActionCore: failed to execute action '$OrchestrationAction' - $_", $_.Exception),
                'Invoke-LabOrchestrationActionCore.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}
