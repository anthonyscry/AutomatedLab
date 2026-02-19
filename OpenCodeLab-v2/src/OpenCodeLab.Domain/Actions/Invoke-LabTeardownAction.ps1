Set-StrictMode -Version Latest

function Invoke-LabTeardownAction {
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full',

        [switch]$Force
    )

    $result = New-LabActionResult -Action 'teardown' -RequestedMode $Mode

    try {
        $policy = Resolve-LabTeardownPolicy -Mode $Mode -Force:$Force
    }
    catch {
        $result.PolicyOutcome = 'PolicyBlocked'
        $result.FailureCategory = 'PolicyBlocked'
        $result.ErrorCode = 'POLICY_EVALUATION_FAILED'
        $result.RecoveryHint = "Policy evaluation failed: $($_.Exception.Message)"
        return $result
    }

    $result.PolicyOutcome = $policy.Outcome
    $result.ErrorCode = $policy.ErrorCode

    if ($policy.Outcome -eq 'PolicyBlocked') {
        $result.FailureCategory = 'PolicyBlocked'
        return $result
    }

    $result.Succeeded = $true
    return $result
}
