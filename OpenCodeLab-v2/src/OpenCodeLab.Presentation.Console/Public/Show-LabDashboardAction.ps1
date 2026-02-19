Set-StrictMode -Version Latest

function Show-LabDashboardAction {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Status,

        [Parameter()]
        [object[]]$Events,

        [Parameter()]
        [object[]]$Diagnostics,

        [Parameter()]
        [switch]$Render
    )

    $frame = Format-LabDashboardFrame -Status $Status -Events $Events -Diagnostics $Diagnostics

    if ($Render) {
        Write-Host $frame
    }

    return $frame
}
