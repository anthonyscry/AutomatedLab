# Ensure-VMsReady.ps1 -- Ensure VM set is ready
function Ensure-VMsReady {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$VMNames,
        [switch]$NonInteractive,
        [switch]$AutoStart
    )

    try {
        if (-not (Ensure-VMRunning -VMNames $VMNames)) {
            if ($NonInteractive -or $AutoStart) {
                Write-Verbose "Auto-starting VMs: $($VMNames -join ', ')"
                $null = Ensure-VMRunning -VMNames $VMNames -AutoStart
            } else {
                $vmList = $VMNames -join ', '
                $start = Read-Host "  $vmList not running. Start now? (y/n)"
                if ($start -ne 'y') { return }
                Write-Verbose "Starting VMs: $($VMNames -join ', ')"
                $null = Ensure-VMRunning -VMNames $VMNames -AutoStart
            }
        }
    }
    catch {
        throw "Ensure-VMsReady: VM readiness check failed - $_"
    }
}
