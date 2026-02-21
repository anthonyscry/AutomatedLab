function Invoke-LabBulkOperation {
    <#
    .SYNOPSIS
        Performs bulk operations against multiple lab VMs.

    .DESCRIPTION
        Invoke-LabBulkOperation starts, stops, suspends, restarts, or checkpoints
        multiple VMs in a single command. Operations execute with per-VM error
        handling so one failure doesn't block other VMs. Results include which
        VMs succeeded, failed, or were skipped with reasons.

    .PARAMETER VMName
        One or more VM names to operate on. Accepts pipeline input.

    .PARAMETER Operation
        Operation type: 'Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint'.

    .PARAMETER CheckpointName
        Checkpoint name (required for 'Checkpoint' operation).

    .PARAMETER Parallel
        Execute operations in parallel for faster completion on large VM sets.

    .PARAMETER WhatIf
        Shows what would happen without executing.

    .EXAMPLE
        Invoke-LabBulkOperation -VMName @('dc1', 'svr1', 'cli1') -Operation Start
        Starts three VMs sequentially.

    .EXAMPLE
        Invoke-LabBulkOperation -VMName @('dc1', 'svr1') -Operation Stop -Parallel
        Stops two VMs in parallel.

    .EXAMPLE
        Get-LabVM | Invoke-LabBulkOperation -Operation Suspend
        Suspends all lab VMs via pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$VMName,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint')]
        [string]$Operation,

        [Parameter(ParameterSetName = 'Checkpoint')]
        [string]$CheckpointName,

        [switch]$Parallel
    )

    begin {
        $allVMs = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($vm in $VMName) {
            $allVMs.Add($vm)
        }
    }

    end {
        if ($allVMs.Count -eq 0) {
            Write-Warning 'No VMs specified for bulk operation'
            return
        }

        $targetList = $allVMs -join ', '
        if (-not $PSCmdlet.ShouldProcess($targetList, $Operation)) {
            return
        }

        $params = @{
            VMName    = @($allVMs)
            Operation = $Operation
            Parallel  = $Parallel
        }

        if ($PSBoundParameters.ContainsKey('CheckpointName')) {
            $params.CheckpointName = $CheckpointName
        }

        $result = Invoke-LabBulkOperationCore @params

        Write-Verbose "Invoke-LabBulkOperation: $($result.Operation) - OverallStatus: $($result.OverallStatus)"
        Write-Verbose "Success: $($result.Success.Count), Failed: $($result.Failed.Count), Skipped: $($result.Skipped.Count)"
        Write-Verbose "Duration: $($result.Duration.ToString('mm\:ss\.fff'))"

        if ($result.Failed.Count -gt 0) {
            foreach ($failure in $result.Failed) {
                Write-Warning "Invoke-LabBulkOperation: $($failure.VMName) failed - $($failure.Error)"
            }
        }

        if ($result.Skipped.Count -gt 0) {
            foreach ($skip in $result.Skipped) {
                Write-Verbose "Invoke-LabBulkOperation: Skipped $skip"
            }
        }

        return $result
    }
}
