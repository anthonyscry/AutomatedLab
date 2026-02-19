Set-StrictMode -Version Latest

function Invoke-LabStatusAction {
    [CmdletBinding()]
    param()

    $result = New-LabActionResult -Action 'status' -RequestedMode 'full'
    $result | Add-Member -MemberType NoteProperty -Name Data -Value (Get-LabVmSnapshot)
    $result.Succeeded = $true
    return $result
}
