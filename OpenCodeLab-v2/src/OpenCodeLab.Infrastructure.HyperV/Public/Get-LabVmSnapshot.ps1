Set-StrictMode -Version Latest

function Get-LabVmSnapshot {
    [CmdletBinding()]
    param()

    $getVmCommand = Get-Command -Name 'Get-VM' -ErrorAction SilentlyContinue
    if ($null -eq $getVmCommand) {
        throw [System.InvalidOperationException]::new('HYPERV_TOOLING_UNAVAILABLE: Get-VM command is unavailable. Enable Hyper-V management tools and retry.')
    }

    return @(Get-VM -ErrorAction Stop | Select-Object -Property Name, State)
}
