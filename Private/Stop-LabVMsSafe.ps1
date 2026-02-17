# Stop-LabVMsSafe.ps1
# Stops all lab VMs safely. Attempts AutomatedLab Stop-LabVM first,
# falls back to Hyper-V Stop-VM for the core VMs.

function Stop-LabVMsSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LabName,
        [Parameter(Mandatory)][string[]]$CoreVMNames
    )

    try {
        Import-LabModule -LabName $LabName
        Stop-LabVM -All -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Get-VM -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @($CoreVMNames) -and $_.State -eq 'Running' } |
            Stop-VM -Force -ErrorAction SilentlyContinue
    }
}
