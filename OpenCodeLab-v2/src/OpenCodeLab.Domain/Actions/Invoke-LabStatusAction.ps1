Set-StrictMode -Version Latest

function Invoke-LabStatusAction {
    [CmdletBinding()]
    param()

    $result = New-LabActionResult -Action 'status' -RequestedMode 'full'

    try {
        $result | Add-Member -MemberType NoteProperty -Name Data -Value (Get-LabVmSnapshot)
        $result.Succeeded = $true
    } catch {
        $result.FailureCategory = 'OperationFailed'
        $errorMessage = $_.Exception.Message

        if ($errorMessage -match '^HYPERV_TOOLING_UNAVAILABLE\b') {
            $result.ErrorCode = 'HYPERV_TOOLING_UNAVAILABLE'
        } else {
            $result.ErrorCode = 'STATUS_SNAPSHOT_FAILED'
        }

        if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
            $result.RecoveryHint = $errorMessage
        }
    }

    return $result
}
