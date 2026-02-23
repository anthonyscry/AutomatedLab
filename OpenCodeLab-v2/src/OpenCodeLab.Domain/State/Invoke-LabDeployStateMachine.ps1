Set-StrictMode -Version Latest

function Invoke-LabDeployStateMachine {
    [CmdletBinding()]
    param(
        [ValidateSet('full')]
        [string]$Mode = 'full'
    )

    return [pscustomobject]@{
        Mode = $Mode
        Steps = @('InitializeDeploy', 'FinalizeDeploy')
    }
}
