Set-StrictMode -Version Latest

function Invoke-LabHealthAction {
    [CmdletBinding()]
    param()

    $result = New-LabActionResult -Action 'health' -RequestedMode 'full'
    $vmSnapshot = Get-LabVmSnapshot

    if (@($vmSnapshot | Where-Object { $_.State -ne 'Running' }).Count -gt 0) {
        $result.FailureCategory = 'OperationFailed'
        $result.ErrorCode = 'VM_NOT_RUNNING'
        return $result
    }

    $result.Succeeded = $true
    return $result
}
