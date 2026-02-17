function Restore-LabCheckpoint {
    <#
    .SYNOPSIS
        Restores all SimpleLab virtual machines to a previous checkpoint.

    .DESCRIPTION
        Restores all lab VMs to a specified checkpoint. VMs are restored in
        reverse dependency order (clients first, then DC). All VMs must have
        a checkpoint with the specified name.

    .PARAMETER CheckpointName
        Name of the checkpoint to restore.

    .PARAMETER SwitchName
        Name of the virtual switch (default: "SimpleLab").

    .OUTPUTS
        PSCustomObject with restore results.

    .EXAMPLE
        Restore-LabCheckpoint -CheckpointName "BeforeConfigChange"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CheckpointName,

        [Parameter()]
        [string]$SwitchName = "SimpleLab"
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        CheckpointName = $CheckpointName
        VMsRestored = @()
        FailedVMs = @()
        SkippedVMs = @()
        OverallStatus = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.OverallStatus = "Failed"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Get VM configurations
        $vmConfigs = Get-LabVMConfig
        if ($null -eq $vmConfigs) {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to retrieve VM configurations"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Restore order: reverse (clients first, then DC) — dynamic from config + auto-detect LIN1
        $configVMs = @(if ($LabVMs) { $LabVMs } elseif (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Lab.CoreVMNames } else { @('dc1','svr1','ws1') })
        $lin1VM = Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
        if ($lin1VM -and ('LIN1' -notin $configVMs)) { $configVMs += 'LIN1' }
        [array]::Reverse($configVMs)
        $restoreOrder = $configVMs

        # Pre-filter: skip missing VMs and VMs without the checkpoint
        $eligibleVMs = @()
        foreach ($vmName in $restoreOrder) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                $result.SkippedVMs += $vmName
                continue
            }
            $checkpoint = Get-VMCheckpoint -VMName $vmName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $CheckpointName }
            if ($null -eq $checkpoint) {
                Write-Warning "Checkpoint '$CheckpointName' not found for VM '$vmName'"
                $result.SkippedVMs += $vmName
                continue
            }
            $eligibleVMs += $vmName
        }

        # Parallel restore via Start-Job
        $cpName = $CheckpointName
        $jobs = @()
        foreach ($vmName in $eligibleVMs) {
            Write-Verbose "Launching restore job for VM '$vmName'..."
            $jobs += Start-Job -Name "restore-$vmName" -ScriptBlock {
                param($vm, $cp)
                Restore-VMCheckpoint -VMName $vm -Name $cp -Confirm:$false -ErrorAction Stop
            } -ArgumentList $vmName, $cpName
        }

        # Wait for all jobs with timeout (120s)
        if ($jobs.Count -gt 0) {
            $null = $jobs | Wait-Job -Timeout 120
        }

        # Collect results
        foreach ($job in $jobs) {
            $vmName = $job.Name -replace '^restore-', ''
            if ($job.State -eq 'Completed') {
                try {
                    $null = Receive-Job -Job $job -ErrorAction Stop
                    $result.VMsRestored += $vmName
                    Write-Verbose "Checkpoint restored for VM '$vmName'"
                }
                catch {
                    Write-Error "Failed to restore checkpoint for VM '$vmName': $($_.Exception.Message)"
                    $result.FailedVMs += $vmName
                }
            }
            else {
                Write-Error "Restore job for VM '$vmName' did not complete (state: $($job.State))"
                $result.FailedVMs += $vmName
                Stop-Job -Job $job -ErrorAction SilentlyContinue
            }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }

        # Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0 -and $result.VMsRestored.Count -gt 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Restored checkpoint '$CheckpointName' for $($result.VMsRestored.Count) VM(s)"
        }
        elseif ($result.VMsRestored.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Restored checkpoint for $($result.VMsRestored.Count) VM(s), failed $($result.FailedVMs.Count), skipped $($result.SkippedVMs.Count)"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to restore checkpoint for any VMs"
        }

        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
