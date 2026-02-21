function Get-LabSnapshotInventory {
    <#
    .SYNOPSIS
        Retrieves a structured inventory of all snapshots across lab VMs.

    .DESCRIPTION
        For each lab VM, enumerates checkpoints and returns structured objects
        with age, creation date, and parent checkpoint information. Useful for
        auditing checkpoint accumulation before pruning.

    .PARAMETER VMName
        Optional list of VM names to filter. Defaults to all lab VMs from
        GlobalLabConfig.Lab.CoreVMNames plus auto-detected Linux VMs (LIN1,
        LINWEB1, LINDB1, LINDOCK1, LINK8S1) from Builder.VMNames.

    .OUTPUTS
        PSCustomObject[] with VMName, CheckpointName, CreationTime, AgeDays, ParentCheckpointName.

    .EXAMPLE
        Get-LabSnapshotInventory
        # Returns all snapshots across all lab VMs

    .EXAMPLE
        Get-LabSnapshotInventory -VMName 'dc1','svr1'
        # Returns snapshots for specific VMs only
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string[]]$VMName
    )

    Set-StrictMode -Version Latest

    try {
        # Determine target VMs
        if ($PSBoundParameters.ContainsKey('VMName')) {
            $targetVMs = $VMName
        }
        else {
            $targetVMs = @(
                if (Test-Path variable:GlobalLabConfig) {
                    $GlobalLabConfig.Lab.CoreVMNames
                }
                else {
                    @('dc1', 'svr1', 'ws1')
                }
            )
            # Auto-detect Linux VMs from Builder config (all 5 Linux roles)
            if (Test-Path variable:GlobalLabConfig) {
                $linuxKeys = @('Ubuntu', 'WebServerUbuntu', 'DatabaseUbuntu', 'DockerUbuntu', 'K8sUbuntu')
                foreach ($key in $linuxKeys) {
                    if ($GlobalLabConfig.Builder.VMNames.ContainsKey($key)) {
                        $linName = $GlobalLabConfig.Builder.VMNames[$key]
                        if ($linName -and $linName -notin $targetVMs) {
                            $linVM = Get-VM -Name $linName -ErrorAction SilentlyContinue
                            if ($linVM) { $targetVMs += $linName }
                        }
                    }
                }
            }
            else {
                # Backward compat: when GlobalLabConfig is not loaded, fall back to LIN1
                $lin1VM = Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
                if ($lin1VM -and ('LIN1' -notin $targetVMs)) {
                    $targetVMs += 'LIN1'
                }
            }
        }

        $results = @()

        foreach ($name in $targetVMs) {
            # Check if VM exists
            $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Verbose "VM '$name' does not exist, skipping"
                continue
            }

            # Get checkpoints for this VM
            $checkpoints = @(Get-VMCheckpoint -VMName $name -ErrorAction SilentlyContinue)
            if ($checkpoints.Count -eq 0) {
                Write-Verbose "No checkpoints found for VM '$name'"
                continue
            }

            foreach ($checkpoint in $checkpoints) {
                $parentName = $checkpoint.ParentCheckpointName
                if ([string]::IsNullOrEmpty($parentName)) {
                    $parentName = '(root)'
                }

                $results += [PSCustomObject]@{
                    VMName               = $name
                    CheckpointName       = $checkpoint.Name
                    CreationTime         = $checkpoint.CreationTime
                    AgeDays              = [math]::Round(((Get-Date) - $checkpoint.CreationTime).TotalDays, 1)
                    ParentCheckpointName = $parentName
                }
            }
        }

        # Sort by CreationTime ascending
        $results = @($results | Sort-Object -Property CreationTime)

        return $results
    }
    catch {
        Write-Error "Failed to get snapshot inventory: $($_.Exception.Message)"
        return @()
    }
}
