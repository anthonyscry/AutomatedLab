# Ensure-VMsReady.ps1 -- Ensure VM set is ready
function Ensure-VMsReady {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$VMNames,
        [switch]$NonInteractive,
        [switch]$AutoStart
    )
    if (-not (Ensure-VMRunning -VMNames $VMNames)) {
        if ($NonInteractive -or $AutoStart) {
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        } else {
            $vmList = $VMNames -join ', '
            $start = Read-Host "  $vmList not running. Start now? (y/n)"
            if ($start -ne 'y') { return }
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        }
    }
}
