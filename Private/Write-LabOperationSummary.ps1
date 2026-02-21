function Write-LabOperationSummary {
    <#
    .SYNOPSIS
        Writes confirmation summary for bulk operations.

    .DESCRIPTION
        Write-LabOperationSummary formats and displays operation completion
        summaries including success/failure/skipped counts, error details,
        duration, and per-step breakdown for workflows. Optionally writes
        summary to run history log for audit trail.

    .PARAMETER Operation
        Operation type that was performed.

    .PARAMETER Result
        Result object from Invoke-LabBulkOperation or Invoke-LabWorkflow.

    .PARAMETER WorkflowMode
        Indicates the result is from a workflow execution (switch).

    .PARAMETER LogToHistory
        Write summary to run history log (switch).

    .OUTPUTS
        [pscustomobject] with formatted summary text, stats, and log path.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [pscustomobject]$Result,

        [switch]$WorkflowMode,

        [switch]$LogToHistory
    )

    $summaryLines = [System.Collections.Generic.List[string]]::new()
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Header
    $summaryLines.Add("=" * 60)
    $summaryLines.Add("Operation Summary: $Operation")
    $summaryLines.Add("Completed: $timestamp")
    $summaryLines.Add("=" * 60)
    $summaryLines.Add("")

    # Overall status
    $statusColor = switch ($Result.OverallStatus) {
        'OK' { 'Green' }
        'Completed' { 'Green' }
        'Partial' { 'Yellow' }
        'Warning' { 'Yellow' }
        'Failed' { 'Red' }
        'Fail' { 'Red' }
        default { 'Gray' }
    }

    $summaryLines.Add("Overall Status: $($Result.OverallStatus)")

    if ($WorkflowMode) {
        $summaryLines.Add("Workflow: $($Result.WorkflowName)")
        $summaryLines.Add("Steps Completed: $($Result.CompletedSteps) / $($Result.TotalSteps)")
        $summaryLines.Add("Failed Steps: $($Result.FailedSteps)")
        $summaryLines.Add("Duration: $($Result.Duration.ToString('mm\:ss\.fff'))")
    }
    else {
        $summaryLines.Add("Operation Count: $($Result.OperationCount)")
        $summaryLines.Add("Duration: $($Result.Duration.ToString('mm\:ss\.fff'))")
        $summaryLines.Add("Parallel: $($Result.Parallel)")
    }

    $summaryLines.Add("")

    # Success/Failed/Skipped breakdown
    if ($WorkflowMode) {
        $summaryLines.Add("-" * 40)
        $summaryLines.Add("Step Results:")
        $summaryLines.Add("")

        foreach ($stepResult in $Result.Results) {
            $stepStatus = switch ($stepResult.Status) {
                'Completed' { '?' }
                'OK' { '?' }
                'Partial' { '?' }
                'Warning' { '?' }
                'Failed' { '?' }
                'Error' { '?' }
                default { '?' }
            }

            $summaryLines.Add("  Step $($stepResult.StepNumber): $stepStatus $($stepResult.Operation)")

            if ($stepResult.VMName -and $stepResult.VMName.Count -gt 0) {
                $summaryLines.Add("    VMs: $($stepResult.VMName -join ', ')")
            }

            if ($stepResult.Error) {
                $summaryLines.Add("    Error: $($stepResult.Error)")
            }

            if ($stepResult.Status -eq 'Partial' -or $stepResult.Status -eq 'Warning') {
                $summaryLines.Add("    Success: $($stepResult.SuccessCount), Failed: $($stepResult.FailedCount), Skipped: $($stepResult.SkippedCount)")
            }

            $summaryLines.Add("")
        }
    }
    else {
        $summaryLines.Add("-" * 40)
        $summaryLines.Add("Results Breakdown:")
        $summaryLines.Add("")

        $summaryLines.Add("  Success: $($Result.Success.Count) VM(s)")
        if ($Result.Success.Count -gt 0) {
            $summaryLines.Add("    $($Result.Success -join ', ')")
        }
        $summaryLines.Add("")

        $summaryLines.Add("  Failed: $($Result.Failed.Count) VM(s)")
        if ($Result.Failed.Count -gt 0) {
            foreach ($failure in $Result.Failed) {
                $summaryLines.Add("    - $($failure.VMName): $($failure.Error)")
            }
        }
        else {
            $summaryLines.Add("    None")
        }
        $summaryLines.Add("")

        $summaryLines.Add("  Skipped: $($Result.Skipped.Count) VM(s)")
        if ($Result.Skipped.Count -gt 0) {
            foreach ($skip in $Result.Skipped) {
                $summaryLines.Add("    - $skip")
            }
        }
        else {
            $summaryLines.Add("    None")
        }
        $summaryLines.Add("")
    }

    # Footer
    $summaryLines.Add("=" * 60)

    # Format for console output
    $consoleOutput = $summaryLines -join "`n"

    # Log to history if requested
    $logPath = $null
    if ($LogToHistory) {
        try {
            $logEntry = [ordered]@{
                Timestamp      = $timestamp
                Operation      = $Operation
                OverallStatus  = $Result.OverallStatus
                SummaryType    = if ($WorkflowMode) { 'Workflow' } else { 'BulkOperation' }
                Result         = $Result
            }

            # Use existing run artifacts infrastructure
            $runId = if ($Result.WorkflowName) {
                "$($Result.WorkflowName)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            } else {
                "$($Operation)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }

            # Write to run logs directory
            $runData = [ordered]@{
                Timestamp      = $timestamp
                Action         = if ($WorkflowMode) { 'Workflow' } else { 'BulkOperation' }
                Operation      = $Operation
                Result         = $Result.OverallStatus
                Duration       = if ($Result.Duration) { $Result.Duration.ToString() } else { $null }
                SuccessCount   = if ($Result.Success) { $Result.Success.Count } elseif ($Result.CompletedSteps) { $Result.CompletedSteps } else { 0 }
                FailedCount    = if ($Result.Failed) { $Result.Failed.Count } elseif ($Result.FailedSteps) { $Result.FailedSteps } else { 0 }
                Summary        = $consoleOutput
            }

            $runLogsDir = Join-Path (Split-Path -Parent $PSScriptRoot) '.planning\run-logs'
            $null = New-Item -Path $runLogsDir -ItemType Directory -Force -ErrorAction SilentlyContinue

            $logFileName = "$runId-summary.json"
            $logFilePath = Join-Path $runLogsDir $logFileName

            $runData | ConvertTo-Json -Depth 4 | Set-Content -Path $logFilePath -Encoding UTF8
            $logPath = $logFilePath

            Write-Verbose "Write-LabOperationSummary: Logged summary to $logFilePath"
        }
        catch {
            Write-Warning "Failed to log operation summary: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        FormattedSummary = $consoleOutput
        Timestamp       = $timestamp
        Operation       = $Operation
        OverallStatus   = $Result.OverallStatus
        LogPath         = $logPath
    }
}
