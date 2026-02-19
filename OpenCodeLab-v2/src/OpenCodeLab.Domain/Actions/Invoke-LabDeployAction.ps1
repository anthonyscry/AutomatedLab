Set-StrictMode -Version Latest

function Invoke-LabDeployAction {
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full'
    )

    $result = New-LabActionResult -Action 'deploy' -RequestedMode $Mode
    $result.EffectiveMode = 'full'

    try {
        $stateResult = Invoke-LabDeployStateMachine -Mode 'full'

        if ($null -ne $stateResult -and $stateResult.PSObject.Properties.Match('Succeeded').Count -gt 0 -and -not $stateResult.Succeeded) {
            $result.FailureCategory = $stateResult.FailureCategory
            $result.ErrorCode = $stateResult.ErrorCode
            $result.RecoveryHint = $stateResult.RecoveryHint
            return $result
        }

        $result.Succeeded = $true
    } catch {
        $result.FailureCategory = 'OperationFailed'
        $result.ErrorCode = 'DEPLOY_STEP_FAILED'

        $exceptionMessage = $_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($exceptionMessage)) {
            $result.RecoveryHint = $exceptionMessage
        }
    }

    return $result
}
