function Invoke-LabBulkOperationCore {
    <#
    .SYNOPSIS
        Executes bulk operations against multiple VMs.

    .DESCRIPTION
        Invoke-LabBulkOperationCore performs the specified operation (Start, Stop,
        Suspend, Restart, Checkpoint) against multiple VMs with per-VM error handling.
        Operations execute with parallel processing support and return detailed
        results including Success, Failed, and Skipped VM lists.

    .PARAMETER VMName
        Array of VM names to operate on.

    .PARAMETER Operation
        Operation type: 'Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint'.

    .PARAMETER CheckpointName
        Checkpoint name (required for 'Checkpoint' operation).

    .PARAMETER Parallel
        Execute operations in parallel (switch).

    .OUTPUTS
        [pscustomobject] with Success (vm[]), Failed (vm[],error[]), Skipped (vm[])
        arrays, OverallStatus (OK/Partial/Failed), Duration (timespan), and
        OperationCount (int).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$VMName,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint')]
        [string]$Operation,

        [string]$CheckpointName,

        [switch]$Parallel
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $success = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[pscustomobject]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()

    $operationBlock = {
        param($vmName, $operation, $checkpointName)

        $ErrorActionPreference = 'Stop'

        try {
            $vm = Get-VM -Name $vmName -ErrorAction Stop

            switch ($operation) {
                'Start' {
                    if ($vm.State -eq 'Running') {
                        return @{ VMName = $vmName; Status = 'Skipped'; Reason = 'Already running' }
                    }
                    Start-VM -Name $vmName -ErrorAction Stop
                    return @{ VMName = $vmName; Status = 'Success' }
                }
                'Stop' {
                    if ($vm.State -eq 'Off') {
                        return @{ VMName = $vmName; Status = 'Skipped'; Reason = 'Already stopped' }
                    }
                    Stop-VM -Name $vmName -Force -ErrorAction Stop
                    return @{ VMName = $vmName; Status = 'Success' }
                }
                'Suspend' {
                    if ($vm.State -ne 'Running') {
                        return @{ VMName = $vmName; Status = 'Skipped'; Reason = "Not running (state: $($vm.State))" }
                    }
                    Suspend-VM -Name $vmName -ErrorAction Stop
                    return @{ VMName = $vmName; Status = 'Success' }
                }
                'Restart' {
                    if ($vm.State -eq 'Off') {
                        return @{ VMName = $vmName; Status = 'Skipped'; Reason = 'VM is off' }
                    }
                    Restart-VM -Name $vmName -Force -ErrorAction Stop
                    return @{ VMName = $vmName; Status = 'Success' }
                }
                'Checkpoint' {
                    if ([string]::IsNullOrWhiteSpace($checkpointName)) {
                        return @{ VMName = $vmName; Status = 'Failed'; Error = 'CheckpointName required' }
                    }
                    Checkpoint-VM -Name $vmName -SnapshotName $checkpointName -ErrorAction Stop
                    return @{ VMName = $vmName; Status = 'Success' }
                }
            }
        }
        catch {
            return @{ VMName = $vmName; Status = 'Failed'; Error = $_.Exception.Message }
        }
    }

    if ($Parallel) {
        $runspaces = [System.Collections.ArrayList]::new()
        $results = [System.Collections.ArrayList]::new()

        foreach ($vm in $VMName) {
            $powershell = [powershell]::Create().AddScript($operationBlock.ToString()).
                AddParameter('vmName', $vm).
                AddParameter('operation', $Operation).
                AddParameter('checkpointName', $CheckpointName)

            $handle = $powershell.BeginInvoke()
            $null = $runspaces.Add(@{ PS = $powershell; Handle = $handle; VM = $vm })
        }

        foreach ($rs in $runspaces) {
            try {
                $rs.Handle.EndInvoke($rs.Handle)
                $result = $rs.PS.EndInvoke($rs.Handle)
                $null = $results.Add($result)
            }
            catch {
                $null = $results.Add(@{
                    VMName = $rs.VM
                    Status = 'Failed'
                    Error = $_.Exception.Message
                })
            }
            finally {
                $rs.PS.Dispose()
            }
        }

        foreach ($result in $results) {
            switch ($result.Status) {
                'Success' { $success.Add($result.VMName) }
                'Skipped' { $skipped.Add("$($result.VMName) ($($result.Reason))") }
                'Failed' {
                    $failed.Add([pscustomobject]@{
                        VMName = $result.VMName
                        Error  = $result.Error
                    })
                }
            }
        }
    }
    else {
        foreach ($vm in $VMName) {
            try {
                $result = & $operationBlock -vmName $vm -operation $Operation -checkpointName $CheckpointName

                switch ($result.Status) {
                    'Success' { $success.Add($result.VMName) }
                    'Skipped' { $skipped.Add("$($result.VMName) ($($result.Reason))") }
                    'Failed' {
                        $failed.Add([pscustomobject]@{
                            VMName = $result.VMName
                            Error  = $result.Error
                        })
                    }
                }
            }
            catch {
                $failed.Add([pscustomobject]@{
                    VMName = $vm
                    Error  = $_.Exception.Message
                })
            }
        }
    }

    $stopwatch.Stop()

    $overallStatus = switch ($failed.Count) {
        { $_ -eq 0 } { 'OK' }
        { $_ -lt $VMName.Count } { 'Partial' }
        default { 'Failed' }
    }

    return [pscustomobject]@{
        Success       = @($success)
        Failed        = @($failed)
        Skipped       = @($skipped)
        OverallStatus = $overallStatus
        Operation     = $Operation
        OperationCount = $VMName.Count
        Duration      = $stopwatch.Elapsed
        Parallel      = $Parallel
    }
}
