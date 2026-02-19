Set-StrictMode -Version Latest

function Get-LabVmSnapshot {
    [CmdletBinding()]
    param()

    $getVmCommand = Get-Command -Name 'Get-VM' -ErrorAction SilentlyContinue
    if ($null -eq $getVmCommand) {
        return @()
    }

    return @(Get-VM | Select-Object -Property Name, State)
}
