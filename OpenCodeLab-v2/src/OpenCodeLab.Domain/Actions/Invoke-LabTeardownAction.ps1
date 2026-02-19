Set-StrictMode -Version Latest

function Invoke-LabTeardownAction {
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full',

        [switch]$Force
    )

    $result = New-LabActionResult -Action 'teardown' -RequestedMode $Mode
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
