function Save-LabCheckpoint {
    <#
    .SYNOPSIS
        Creates checkpoints for all SimpleLab virtual machines.

    .DESCRIPTION
        Creates Hyper-V checkpoints for all lab VMs, useful for saving state
        before making changes or testing. Creates checkpoints in dependency order.

    .PARAMETER CheckpointName
        Name for the checkpoint (default: Auto-generated timestamp).

    .PARAMETER SwitchName
        Name of the virtual switch (default: "SimpleLab").

    .OUTPUTS
        PSCustomObject with checkpoint creation results.

    .EXAMPLE
        Save-LabCheckpoint -CheckpointName "BeforeConfigChange"

    .EXAMPLE
        Save-LabCheckpoint
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$CheckpointName,

        [Parameter()]
        [string]$SwitchName = "SimpleLab"
    )

    # Start timing
    $startTime = Get-Date

    # Generate checkpoint name if not provided
    if ([string]::IsNullOrWhiteSpace($CheckpointName)) {
        $CheckpointName = "SimpleLab_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    }

    # Initialize result object
    $result = [PSCustomObject]@{
        CheckpointName = $CheckpointName
        VMsCheckpointed = @()
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

        # Checkpoint order: DC first, then servers, then clients (dynamic from config + auto-detect LIN1)
        $checkpointOrder = @(if ($LabVMs) { $LabVMs } elseif (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Lab.CoreVMNames } else { @('dc1','svr1','ws1') })
        $lin1VM = Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
        if ($lin1VM -and ('LIN1' -notin $checkpointOrder)) { $checkpointOrder += 'LIN1' }

        # Pre-filter: skip missing/invalid VMs, collect eligible ones
        $eligibleVMs = @()
        foreach ($vmName in $checkpointOrder) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$vmName' does not exist, skipping"
                $result.SkippedVMs += $vmName
                continue
            }
            if ($vm.State -notin @("Running", "Off", "Saved")) {
                Write-Warning "VM '$vmName' is in state '$($vm.State)' - cannot create checkpoint"
                $result.SkippedVMs += $vmName
                continue
            }
            $eligibleVMs += $vmName
        }

        # Parallel checkpoint creation via Start-Job
        $cpName = $CheckpointName
        $jobs = @()
        foreach ($vmName in $eligibleVMs) {
            Write-Verbose "Launching checkpoint job for VM '$vmName'..."
            $jobs += Start-Job -Name "cp-$vmName" -ScriptBlock {
                param($vm, $cp)
                Checkpoint-VM -Name $vm -SnapshotName $cp -ErrorAction Stop
            } -ArgumentList $vmName, $cpName
        }

        # Wait for all jobs with timeout (120s)
        if ($jobs.Count -gt 0) {
            $null = $jobs | Wait-Job -Timeout 120
        }

        # Collect results
        foreach ($job in $jobs) {
            $vmName = $job.Name -replace '^cp-', ''
            if ($job.State -eq 'Completed') {
                try {
                    $null = Receive-Job -Job $job -ErrorAction Stop
                    $result.VMsCheckpointed += $vmName
                    Write-Verbose "Checkpoint created for VM '$vmName'"
                }
                catch {
                    Write-Error "Failed to create checkpoint for VM '$vmName': $($_.Exception.Message)"
                    $result.FailedVMs += $vmName
                }
            }
            else {
                Write-Error "Checkpoint job for VM '$vmName' did not complete (state: $($job.State))"
                $result.FailedVMs += $vmName
                Stop-Job -Job $job -ErrorAction SilentlyContinue
            }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }

        # Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Created checkpoint '$CheckpointName' for $($result.VMsCheckpointed.Count) VM(s)"
        }
        elseif ($result.VMsCheckpointed.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Created checkpoint for $($result.VMsCheckpointed.Count) VM(s), failed $($result.FailedVMs.Count), skipped $($result.SkippedVMs.Count)"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to create checkpoint for any VMs"
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
