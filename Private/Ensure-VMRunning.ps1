# Ensure-VMRunning.ps1 -- Ensure Hyper-V VM(s) are running
function Ensure-VMRunning {
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string[]] $VMNames,
        [switch] $AutoStart
    )
    $missing = @()
    foreach ($n in $VMNames) {
        $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
        if (-not $vm) { $missing += $n; continue }
        if ($vm.State -ne 'Running') {
            if ($AutoStart) {
                try {
                    Start-VM -Name $n -ErrorAction Stop
                    Write-Verbose "[Ensure-VMRunning] Started VM '$n'"
                } catch {
                    # VM may have started between our check and this call
                    $refreshedVm = Get-VM -Name $n -ErrorAction SilentlyContinue
                    if (-not $refreshedVm -or $refreshedVm.State -ne 'Running') {
                        throw "Failed to start VM '$n': $($_.Exception.Message)"
                    }
                }
            } else {
                return $false
            }
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing Hyper-V VM(s): $($missing -join ', ')"
    }
    # If we autostarted, poll for network adapters instead of fixed sleep
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $allReady = $true
        foreach ($n in $VMNames) {
            $adapters = Get-VMNetworkAdapter -VMName $n -ErrorAction SilentlyContinue
            if (-not $adapters -or ($adapters.IPAddresses.Count -eq 0)) {
                $allReady = $false
                break
            }
        }
        if ($allReady) { break }
        Start-Sleep -Milliseconds 500
    }
    return $true
}
