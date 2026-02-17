# Test-LabReadySnapshot.ps1
# Checks whether a LabReady snapshot exists on all specified or expected VMs.
# Returns $true if all targets have a LabReady snapshot, $false otherwise.

function Test-LabReadySnapshot {
    [CmdletBinding()]
    param(
        [string[]]$VMNames,
        [Parameter(Mandatory)][string]$LabName,
        [string[]]$CoreVMNames = @()
    )

    try {
        Import-LabModule -LabName $LabName
        $targets = @()
        if ($VMNames -and $VMNames.Count -gt 0) {
            $targets = @($VMNames)
        }
        elseif ($CoreVMNames -and $CoreVMNames.Count -gt 0) {
            $targets = @($CoreVMNames)
        }

        foreach ($vmName in $targets) {
            $snap = Get-VMSnapshot -VMName $vmName -Name 'LabReady' -ErrorAction SilentlyContinue
            if (-not $snap) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}
