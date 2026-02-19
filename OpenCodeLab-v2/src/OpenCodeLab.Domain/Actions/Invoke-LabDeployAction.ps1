Set-StrictMode -Version Latest

function Invoke-LabDeployAction {
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full'
    )

    $result = New-LabActionResult -Action 'deploy' -RequestedMode $Mode

    try {
        Invoke-LabDeployStateMachine -Mode 'full' | Out-Null
        $result.EffectiveMode = 'full'
        $result.Succeeded = $true
    } catch {
        $result.FailureCategory = 'OperationFailed'
        $result.ErrorCode = 'DEPLOY_STEP_FAILED'
    }

    return $result
}
