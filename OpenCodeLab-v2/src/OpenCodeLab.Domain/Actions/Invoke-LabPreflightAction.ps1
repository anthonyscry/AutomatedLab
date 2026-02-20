Set-StrictMode -Version Latest

function Invoke-LabPreflightAction {
    [CmdletBinding()]
    param()

    $result = New-LabActionResult -Action 'preflight' -RequestedMode 'full'
    $remediation = 'Enable Hyper-V and rerun preflight.'

    try {
        $probe = Test-HyperVPrereqs
    } catch {
        $result.FailureCategory = 'PreflightFailed'
        $result.ErrorCode = 'PREFLIGHT_PROBE_FAILED'
        $probeError = $_.Exception.Message
        $result.RecoveryHint = if ([string]::IsNullOrWhiteSpace($probeError)) {
            $remediation
        } elseif ($probeError -match '(?i)Enable Hyper-V') {
            $probeError
        } else {
            "$probeError $remediation"
        }

        return $result
    }

    if (-not $probe.Ready) {
        $result.FailureCategory = 'PreflightFailed'
        $result.ErrorCode = 'PREFLIGHT_PREREQ_NOT_READY'
        $result.RecoveryHint = if ([string]::IsNullOrWhiteSpace($probe.Reason)) {
            $remediation
        } elseif ($probe.Reason -match '(?i)Enable Hyper-V') {
            $probe.Reason
        } else {
            "$($probe.Reason) $remediation"
        }

        return $result
    }

    $result.Succeeded = $true
    return $result
}
