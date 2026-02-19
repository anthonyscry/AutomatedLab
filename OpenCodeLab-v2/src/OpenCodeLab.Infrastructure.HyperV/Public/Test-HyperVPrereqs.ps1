Set-StrictMode -Version Latest

function Test-HyperVPrereqs {
    [CmdletBinding()]
    param()

    $getVmCommand = Get-Command -Name 'Get-VM' -ErrorAction SilentlyContinue
    if ($null -eq $getVmCommand) {
        return [pscustomobject]@{
            Ready  = $false
            Reason = 'Hyper-V cmdlets are unavailable. Enable Hyper-V and rerun preflight.'
        }
    }

    return [pscustomobject]@{
        Ready  = $true
        Reason = $null
    }
}
