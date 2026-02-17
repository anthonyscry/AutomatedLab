function Resolve-LabDispatchPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [ValidateSet('quick', 'full')]
        [string]$Mode = 'full'
    )

    try {
        $dispatchAction = $Action
        $orchestrationAction = $null
        $resolvedMode = $Mode

        switch ($Action) {
            'deploy' {
                $orchestrationAction = 'deploy'
            }
            'teardown' {
                $orchestrationAction = 'teardown'
            }
            'setup' {
                $resolvedMode = 'full'
            }
            'one-button-setup' {
                $resolvedMode = 'full'
            }
            'one-button-reset' {
                $resolvedMode = 'full'
            }
            'blow-away' {
                $resolvedMode = 'full'
            }
        }

        return [pscustomobject]@{
            DispatchAction = $dispatchAction
            OrchestrationAction = $orchestrationAction
            Mode = $resolvedMode
        }
    }
    catch {
        throw "Resolve-LabDispatchPlan: failed to resolve dispatch plan - $_"
    }
}
