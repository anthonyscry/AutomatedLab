Set-StrictMode -Version Latest

function Show-LabDashboardAction {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Status,

        [Parameter()]
        [object[]]$Events,

        [Parameter()]
        [object[]]$Diagnostics
    )

    $frame = Format-LabDashboardFrame -Status $Status -Events $Events -Diagnostics $Diagnostics
    Write-Host $frame

    return $frame
}
