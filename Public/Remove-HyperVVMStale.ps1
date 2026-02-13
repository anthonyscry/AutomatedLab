# Remove-HyperVVMStale.ps1 -- Remove stale Hyper-V VM safely
function Remove-HyperVVMStale {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VMName,
        [Parameter()][string]$Context = 'cleanup',
        [Parameter()][int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vm) { return $true }

        Write-LabStatus -Status WARN -Message "Found VM '$VMName' during $Context (attempt $attempt/$MaxAttempts). Removing..." -Indent 2

        Hyper-V\Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMSnapshot -ErrorAction SilentlyContinue | Out-Null

        Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMDvdDrive -ErrorAction SilentlyContinue | Out-Null

        if ($vm.State -like 'Saved*') {
            Hyper-V\Remove-VMSavedState -VMName $VMName -ErrorAction SilentlyContinue | Out-Null
            $savedStateDeadline = [datetime]::Now.AddSeconds(10)
            while ([datetime]::Now -lt $savedStateDeadline) {
                $savedStateVm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
                if (-not $savedStateVm -or $savedStateVm.State -notlike 'Saved*') { break }
                Start-Sleep -Seconds 1
            }
            $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        }

        if ($vm -and $vm.State -ne 'Off') {
            Hyper-V\Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null
            $stopDeadline = [datetime]::Now.AddSeconds(20)
            while ([datetime]::Now -lt $stopDeadline) {
                $stoppedVm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
                if (-not $stoppedVm -or $stoppedVm.State -eq 'Off') { break }
                Start-Sleep -Seconds 1
            }
        }

        Hyper-V\Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
        $removeDeadline = [datetime]::Now.AddSeconds(20)
        while ([datetime]::Now -lt $removeDeadline) {
            $removedVm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
            if (-not $removedVm) { break }
            Start-Sleep -Seconds 1
        }

        $stillThere = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $stillThere) {
            Write-LabStatus -Status OK -Message "Removed VM '$VMName'" -Indent 2
            return $true
        }

        $vmId = $stillThere.VMId.Guid
        $vmwp = Get-CimInstance Win32_Process -Filter "Name='vmwp.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$vmId*" } |
            Select-Object -First 1
        if ($vmwp) {
            Stop-Process -Id $vmwp.ProcessId -Force -ErrorAction SilentlyContinue
            $vmwpDeadline = [datetime]::Now.AddSeconds(10)
            while ([datetime]::Now -lt $vmwpDeadline) {
                $vmwpAlive = Get-CimInstance Win32_Process -Filter "ProcessId=$($vmwp.ProcessId)" -ErrorAction SilentlyContinue
                if (-not $vmwpAlive) { break }
                Start-Sleep -Seconds 1
            }
        }
    }

    return -not (Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue)
}
