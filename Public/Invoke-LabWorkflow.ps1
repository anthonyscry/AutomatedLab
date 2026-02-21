function Invoke-LabWorkflow {
    <#
    .SYNOPSIS
        Executes a custom operational workflow.

    .DESCRIPTION
        Invoke-LabWorkflow runs a predefined workflow, executing each step
        in sequence with error handling. Workflows can start, stop, suspend,
        or checkpoint VMs with optional delays between steps. Failed steps
        are logged but don't stop workflow execution unless -StopOnError.

    .PARAMETER Name
        Name of the workflow to execute.

    .PARAMETER StopOnError
        Stop workflow execution if any step fails.

    .PARAMETER WhatIf
        Shows what would happen without executing.

    .EXAMPLE
        Invoke-LabWorkflow -Name 'StartLab'
        Executes the StartLab workflow.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$StopOnError
    )

    $workflowConfig = Get-LabWorkflowConfig

    if (-not $workflowConfig.Enabled) {
        throw 'Workflows are disabled in Lab configuration'
    }

    $workflow = Get-LabWorkflow -Name $Name

    if (-not $workflow) {
        throw "Workflow not found: $Name"
    }

    $targetSteps = $workflow.Steps.Count
    if (-not $PSCmdlet.ShouldProcess($Name, "Execute $targetSteps workflow steps")) {
        return
    }

    Write-Verbose "Invoke-LabWorkflow: Executing workflow '$Name' ($($workflow.StepCount) steps)"

    $results = [System.Collections.Generic.List[pscustomobject]]::new()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($step in $workflow.Steps) {
        $stepNum = $results.Count + 1

        Write-Verbose "Invoke-LabWorkflow: Step $stepNum/$($workflow.StepCount) - $($step.Operation)"

        $stepResult = [ordered]@{
            StepNumber = $stepNum
            Operation  = $step.Operation
            Status     = 'Pending'
            VMName     = if ($step.VMName) { @($step.VMName) } else { @() }
            Error      = $null
        }

        try {
            $operationParams = @{
                Operation = $step.Operation
            }

            if ($step.VMName -and $step.VMName.Count -gt 0) {
                $operationParams.VMName = @($step.VMName)
            }

            if ($step.CheckpointName) {
                $operationParams.CheckpointName = $step.CheckpointName
            }

            $result = Invoke-LabBulkOperation @operationParams

            $stepResult.Status = $result.OverallStatus
            $stepResult.SuccessCount = $result.Success.Count
            $stepResult.FailedCount = $result.Failed.Count
            $stepResult.SkippedCount = $result.Skipped.Count

            if ($result.OverallStatus -eq 'Failed' -and $StopOnError) {
                $stepResult.Error = 'Operation failed and StopOnError specified'
                $results.Add([pscustomobject]$stepResult)
                throw "Workflow stopped at step $stepNum due to failure"
            }
        }
        catch {
            $stepResult.Status = 'Error'
            $stepResult.Error = $_.Exception.Message

            if ($StopOnError) {
                $results.Add([pscustomobject]$stepResult)
                throw
            }
        }

        $results.Add([pscustomobject]$stepResult)

        if ($step.DelaySeconds -gt 0) {
            Write-Verbose "Invoke-LabWorkflow: Delaying $($step.DelaySeconds) seconds before next step"
            Start-Sleep -Seconds $step.DelaySeconds
        }
    }

    $stopwatch.Stop()

    $failedSteps = @($results | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'Failed' })
    $overallStatus = switch ($failedSteps.Count) {
        { $_ -eq 0 } { 'Completed' }
        { $_ -lt $results.Count } { 'Partial' }
        default { 'Failed' }
    }

    $result = [pscustomobject]@{
        WorkflowName  = $Name
        OverallStatus = $overallStatus
        TotalSteps    = $workflow.StepCount
        CompletedSteps = $results.Count
        FailedSteps   = $failedSteps.Count
        Results       = @($results)
        Duration      = $stopwatch.Elapsed
    }

    # Generate summary for workflow execution
    $summary = Write-LabOperationSummary -Operation $Name -Result $result -WorkflowMode -LogToHistory

    # Display summary
    Write-Host $summary.FormattedSummary

    return [pscustomobject]@{
        WorkflowName   = $result.WorkflowName
        OverallStatus  = $result.OverallStatus
        TotalSteps     = $result.TotalSteps
        CompletedSteps = $result.CompletedSteps
        FailedSteps    = $result.FailedSteps
        Results        = $result.Results
        Duration       = $result.Duration
        Summary        = $summary
    }
}
