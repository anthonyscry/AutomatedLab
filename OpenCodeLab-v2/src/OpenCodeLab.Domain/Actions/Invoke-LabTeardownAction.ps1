Set-StrictMode -Version Latest

function Invoke-LabTeardownAction {
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full',

        [switch]$Force,

        [ValidateNotNullOrEmpty()]
        [string]$LockPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../../../artifacts/logs/run.lock'))
    )

    $result = New-LabActionResult -Action 'teardown' -RequestedMode $Mode
    $lockHandle = $null

    try {
        $lockHandle = Enter-LabRunLock -LockPath $LockPath
        $policy = Resolve-LabTeardownPolicy -Mode $Mode -Force:$Force

        $result.PolicyOutcome = $policy.Outcome
        $result.ErrorCode = $policy.ErrorCode

        if ($policy.Outcome -eq 'PolicyBlocked') {
            $result.FailureCategory = 'PolicyBlocked'
            return $result
        }

        $result.Succeeded = $true
        return $result
    }
    catch {
        $errorMessage = $_.Exception.Message
        $result.PolicyOutcome = 'PolicyBlocked'
        $result.FailureCategory = 'PolicyBlocked'

        if ($errorMessage -match '^PolicyBlocked:') {
            $result.ErrorCode = 'RUN_LOCK_ACTIVE'
            $result.RecoveryHint = $errorMessage
        }
        else {
            $result.ErrorCode = 'POLICY_EVALUATION_FAILED'
            $result.RecoveryHint = "Policy evaluation failed: $errorMessage"
        }

        return $result
    }
    finally {
        if ($null -ne $lockHandle) {
            Exit-LabRunLock -LockHandle $lockHandle
        }
    }
}
