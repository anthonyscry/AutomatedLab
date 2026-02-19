Set-StrictMode -Version Latest

function Invoke-LabHealthAction {
    [CmdletBinding()]
    param()

    $result = New-LabActionResult -Action 'health' -RequestedMode 'full'

    try {
        $vmSnapshot = Get-LabVmSnapshot
    } catch {
        $result.FailureCategory = 'OperationFailed'
        $errorMessage = $_.Exception.Message

        if ($errorMessage -match '^HYPERV_TOOLING_UNAVAILABLE\b') {
            $result.ErrorCode = 'HYPERV_TOOLING_UNAVAILABLE'
        } else {
            $result.ErrorCode = 'HEALTH_SNAPSHOT_FAILED'
        }

        if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
            $result.RecoveryHint = $errorMessage
        }

        return $result
    }

    if (@($vmSnapshot | Where-Object { $_.State -ne 'Running' }).Count -gt 0) {
        $result.FailureCategory = 'OperationFailed'
        $result.ErrorCode = 'VM_NOT_RUNNING'
        return $result
    }

    $result.Succeeded = $true
    return $result
}
