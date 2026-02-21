# Write-LabRunArtifacts.ps1
# Writes JSON and TXT run artifact files for an OpenCodeLab orchestration run.
# All values previously read from script-scope variables are passed via ReportData hashtable.

function Write-LabRunArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$ReportData,
        [Parameter(Mandatory)][bool]$Success,
        [string]$ErrorMessage = ''
    )

    try {
        $runLogRoot = $ReportData.RunLogRoot
        $runId = $ReportData.RunId
        $runStart = $ReportData.RunStart

        if (-not (Test-Path $runLogRoot)) {
            $null = New-Item -Path $runLogRoot -ItemType Directory -Force
            Write-Verbose "Created directory: $runLogRoot"
        }

        $ended = Get-Date
        $duration = [int]($ended - $runStart).TotalSeconds
        $baseName = "OpenCodeLab-Run-$runId"
        $jsonPath = Join-Path $runLogRoot "$baseName.json"
        $txtPath = Join-Path $runLogRoot "$baseName.txt"

        $hostOutcomes = if ($null -ne $ReportData.HostOutcomes) { @($ReportData.HostOutcomes) } else { @() }
        $blastRadius = if ($null -ne $ReportData.BlastRadius) { @($ReportData.BlastRadius) } else { @() }
        $runEvents = if ($null -ne $ReportData.RunEvents) { $ReportData.RunEvents } else { @() }

        $report = [pscustomobject]@{
            run_id = $runId
            action = $ReportData.Action
            dispatch_mode = $ReportData.ResolvedDispatchMode
            execution_outcome = $ReportData.ExecutionOutcome
            execution_started_at = $ReportData.ExecutionStartedAt
            execution_completed_at = $ReportData.ExecutionCompletedAt
            requested_mode = $ReportData.RequestedMode
            effective_mode = $ReportData.EffectiveMode
            fallback_reason = $ReportData.FallbackReason
            profile_source = $ReportData.ProfileSource
            noninteractive = [bool]$ReportData.NonInteractive
            core_only = [bool]$ReportData.CoreOnly
            force = [bool]$ReportData.Force
            remove_network = [bool]$ReportData.RemoveNetwork
            dry_run = [bool]$ReportData.DryRun
            auto_heal = $ReportData.AutoHeal
            defaults_file = $ReportData.DefaultsFile
            started_utc = $runStart.ToUniversalTime().ToString('o')
            ended_utc = $ended.ToUniversalTime().ToString('o')
            duration_seconds = $duration
            success = $Success
            error = $ErrorMessage
            policy_outcome = $ReportData.PolicyOutcome
            policy_reason = $ReportData.PolicyReason
            host_outcomes = $hostOutcomes
            blast_radius = $blastRadius
            host = $env:COMPUTERNAME
            user = "$env:USERDOMAIN\$env:USERNAME"
            events = $runEvents
        }

        $report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

        $lines = @(
            "run_id: $runId",
            "action: $($ReportData.Action)",
            "dispatch_mode: $($ReportData.ResolvedDispatchMode)",
            "execution_outcome: $($ReportData.ExecutionOutcome)",
            "execution_started_at: $($ReportData.ExecutionStartedAt)",
            "execution_completed_at: $($ReportData.ExecutionCompletedAt)",
            "requested_mode: $($ReportData.RequestedMode)",
            "effective_mode: $($ReportData.EffectiveMode)",
            "fallback_reason: $($ReportData.FallbackReason)",
            "profile_source: $($ReportData.ProfileSource)",
            "core_only: $($ReportData.CoreOnly)",
            "success: $Success",
            "started_utc: $($runStart.ToUniversalTime().ToString('o'))",
            "ended_utc: $($ended.ToUniversalTime().ToString('o'))",
            "duration_seconds: $duration",
            "error: $ErrorMessage",
            "policy_outcome: $($ReportData.PolicyOutcome)",
            "policy_reason: $($ReportData.PolicyReason)",
            "host_outcomes: $((@($hostOutcomes | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'HostName') { [string]$_.HostName } else { 'unknown' } }) -join ','))",
            "blast_radius: $($blastRadius -join ',')",
            "host: $env:COMPUTERNAME",
            "user: $env:USERDOMAIN\$env:USERNAME",
            "events:"
        )

        foreach ($runEvent in $runEvents) {
            $lines += "- [$($runEvent.Time)] $($runEvent.Step) :: $($runEvent.Status) :: $($runEvent.Message)"
        }

        $lines | Set-Content -Path $txtPath -Encoding UTF8
        Write-Host "`n  Run report: $jsonPath" -ForegroundColor DarkGray
        Write-Host "  Run summary: $txtPath" -ForegroundColor DarkGray

        # Track analytics event based on action type
        $analyticsEventType = switch ($ReportData.Action) {
            'bootstrap' { 'LabDeployed' }
            'deploy'    { 'LabDeployed' }
            'teardown'  { 'LabTeardown' }
            default     { "Lab$($ReportData.Action)" }
        }

        $analyticsMetadata = [ordered]@{
            Action          = $ReportData.Action
            Mode            = $ReportData.EffectiveMode
            Success         = $Success
            DurationSeconds = $duration
            RunId           = $runId
        }

        if ($ReportData.VMNames -and $ReportData.VMNames.Count -gt 0) {
            $analyticsMetadata.VMCount = $ReportData.VMNames.Count
        }

        Write-LabAnalyticsEvent -EventType $analyticsEventType -LabName $ReportData.LabName -VMNames $ReportData.VMNames -Metadata $analyticsMetadata
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Write-LabRunArtifacts: failed to write run artifacts to '$($ReportData.RunLogRoot)' - $_", $_.Exception),
                'Write-LabRunArtifacts.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}
