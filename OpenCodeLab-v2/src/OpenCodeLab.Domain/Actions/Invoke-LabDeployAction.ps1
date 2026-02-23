Set-StrictMode -Version Latest

function Invoke-LabDeployAction {
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full',

        [ValidateNotNullOrEmpty()]
        [string]$LockPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../../../artifacts/logs/run.lock'))
    )

    $result = New-LabActionResult -Action 'deploy' -RequestedMode $Mode
    $result.EffectiveMode = 'full'
    $lockHandle = $null

    try {
        $lockHandle = Enter-LabRunLock -LockPath $LockPath
        $stateResult = Invoke-LabDeployStateMachine -Mode 'full'

        if ($null -ne $stateResult -and $stateResult.PSObject.Properties.Match('Succeeded').Count -gt 0 -and -not $stateResult.Succeeded) {
            $result.FailureCategory = $stateResult.FailureCategory
            $result.ErrorCode = $stateResult.ErrorCode
            $result.RecoveryHint = $stateResult.RecoveryHint
            return $result
        }

        $result.Succeeded = $true
    } catch {
        $exceptionMessage = $_.Exception.Message

        if ($exceptionMessage -match '^PolicyBlocked:') {
            $result.FailureCategory = 'PolicyBlocked'
            $result.ErrorCode = 'RUN_LOCK_ACTIVE'
            $result.RecoveryHint = $exceptionMessage
        }
        else {
            $result.FailureCategory = 'OperationFailed'
            $result.ErrorCode = 'DEPLOY_STEP_FAILED'
            if (-not [string]::IsNullOrWhiteSpace($exceptionMessage)) {
                $result.RecoveryHint = $exceptionMessage
            }
        }
    }
    finally {
        if ($null -ne $lockHandle) {
            Exit-LabRunLock -LockHandle $lockHandle
        }
    }

    return $result
}
