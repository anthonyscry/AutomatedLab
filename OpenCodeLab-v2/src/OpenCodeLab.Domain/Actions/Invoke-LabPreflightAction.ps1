Set-StrictMode -Version Latest

function Invoke-LabPreflightAction {
    [CmdletBinding()]
    param()

    $probe = Test-HyperVPrereqs
    $result = New-LabActionResult -Action 'preflight' -RequestedMode 'full'

    if (-not $probe.Ready) {
        $result.FailureCategory = 'PreflightFailed'
        $result.RecoveryHint = if ([string]::IsNullOrWhiteSpace($probe.Reason)) {
            'Enable Hyper-V and rerun preflight.'
        } else {
            "$($probe.Reason) Enable Hyper-V and rerun preflight."
        }

        return $result
    }

    $result.Succeeded = $true
    return $result
}
