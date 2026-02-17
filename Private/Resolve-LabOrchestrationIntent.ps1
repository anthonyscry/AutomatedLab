function Resolve-LabOrchestrationIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('deploy', 'teardown')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$EffectiveMode
    )

    try {
        $strategy = '{0}-{1}' -f $Action, $EffectiveMode

        return [pscustomobject]@{
            Strategy = $strategy
            RunDeployScript = ($Action -eq 'deploy' -and $EffectiveMode -eq 'full')
            RunQuickStartupSequence = ($Action -eq 'deploy' -and $EffectiveMode -eq 'quick')
            RunQuickReset = ($Action -eq 'teardown' -and $EffectiveMode -eq 'quick')
            RunBlowAway = ($Action -eq 'teardown' -and $EffectiveMode -eq 'full')
        }
    }
    catch {
        throw "Resolve-LabOrchestrationIntent: failed to resolve orchestration intent - $_"
    }
}
