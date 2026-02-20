# Remove-HyperVVMStale.ps1 -- Remove stale Hyper-V VM safely
function Remove-HyperVVMStale {
    <#
    .SYNOPSIS
    Safely remove a stale Hyper-V VM including snapshots and saved state.

    .DESCRIPTION
    Attempts to cleanly remove a named Hyper-V VM with up to MaxAttempts retries.
    On each attempt the function: removes all checkpoints/snapshots, detaches DVD
    drives, clears any saved state, force-stops the VM if it is still running,
    and then removes the VM.  If the VM process (vmwp.exe) is still alive after
    removal it is terminated before the next attempt.  Returns $true if the VM no
    longer exists after the final attempt, $false otherwise.

    .PARAMETER VMName
    Name of the Hyper-V VM to remove.

    .PARAMETER Context
    Descriptive label for log messages indicating why the cleanup is happening
    (default: cleanup).

    .PARAMETER MaxAttempts
    Maximum number of removal attempts before giving up (default: 3).

    .EXAMPLE
    Remove-HyperVVMStale -VMName 'LIN1'
    # Removes VM 'LIN1' with default 3 attempts and logs context 'cleanup'.

    .EXAMPLE
    $removed = Remove-HyperVVMStale -VMName 'GoldenTemplate-20260219' -Context 'golden-template-cleanup'
    if (-not $removed) { Write-Warning 'VM could not be removed — check Hyper-V event log.' }

    .EXAMPLE
    # Use in a cleanup block after a failed lab provisioning run
    'LIN1','LIN2','LIN3' | ForEach-Object { Remove-HyperVVMStale -VMName $_ -Context 'rollback' }
    #>
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

        Write-Verbose "Removing snapshots for VM '$VMName'..."
        $null = Hyper-V\Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMSnapshot -ErrorAction SilentlyContinue

        $null = Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMDvdDrive -ErrorAction SilentlyContinue

        if ($vm.State -like 'Saved*') {
            Write-Verbose "Removing saved state for VM '$VMName'..."
            $null = Hyper-V\Remove-VMSavedState -VMName $VMName -ErrorAction SilentlyContinue
            $savedStateDeadline = [datetime]::Now.AddSeconds(10)
            while ([datetime]::Now -lt $savedStateDeadline) {
                $savedStateVm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
                if (-not $savedStateVm -or $savedStateVm.State -notlike 'Saved*') { break }
                Start-Sleep -Seconds 1
            }
            $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        }

        if ($vm -and $vm.State -ne 'Off') {
            Write-Verbose "Force stopping VM '$VMName'..."
            $null = Hyper-V\Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue
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
