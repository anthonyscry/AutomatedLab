function Measure-LabVMOperation {
    <#
    .SYNOPSIS
        Measures the execution time of a lab VM operation and records it as a performance metric.

    .DESCRIPTION
        Measure-LabVMOperation executes a scriptblock and records the duration and success
        status as a performance metric. The metric is automatically written to the performance
        log if performance tracking is enabled. Returns the result of the scriptblock or
        re-throws any exception.

    .PARAMETER Operation
        Type of operation being measured: 'VMStart', 'VMStop', 'VMSuspend',
        'VMCheckpoint', 'VMRestore', etc.

    .PARAMETER VMName
        Name of the VM this operation relates to.

    .PARAMETER ScriptBlock
        The scriptblock to measure and execute.

    .PARAMETER Metadata
        Additional metric metadata as hashtable (optional).

    .EXAMPLE
        Measure-LabVMOperation -Operation 'VMStart' -VMName 'dc1' -ScriptBlock { Start-VM -Name 'dc1' }

    .EXAMPLE
        $result = Measure-LabVMOperation -Operation 'Checkpoint' -VMName 'svr1' -Metadata @{ CheckpointType = 'Standard' } -ScriptBlock {
            Save-LabCheckpoint -VMName 'svr1' -SnapshotName 'before-install'
        }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [hashtable]$Metadata = @{}
    )

    $performanceConfig = Get-LabPerformanceConfig

    if (-not $performanceConfig.Enabled) {
        return & $ScriptBlock
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $success = $false
    $result = $null
    $errorRecord = $null

    try {
        $result = & $ScriptBlock
        $success = $true
        return $result
    }
    catch {
        $errorRecord = $_
        throw
    }
    finally {
        $stopwatch.Stop()

        $metricMetadata = if ($null -ne $errorRecord) {
            $merged = @{} + $Metadata
            $merged['Error'] = $errorRecord.Exception.Message
            $merged['ErrorType'] = $errorRecord.Exception.GetType().Name
            $merged
        } else {
            $Metadata
        }

        Write-LabPerformanceMetric -Operation $Operation -VMName $VMName -Duration $stopwatch.ElapsedMilliseconds -Success $success -Metadata $metricMetadata
    }
}

