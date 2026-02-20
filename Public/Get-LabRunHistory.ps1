function Get-LabRunHistory {
    <#
    .SYNOPSIS
        Retrieves run history entries from OpenCodeLab run artifact files.

    .DESCRIPTION
        Get-LabRunHistory reads run artifact JSON files from the lab log directory and
        returns either a summary table of the last N runs (list mode) or the full detail
        of a specific run (detail mode).

        List mode (default): Returns PSCustomObject entries with key fields sorted by
        EndedUtc descending (newest first), limited to the last $Last entries.

        Detail mode (-RunId): Returns the full PSCustomObject parsed from the JSON
        artifact for the specified run ID, including all events, host outcomes, and
        metadata fields.

    .PARAMETER RunId
        When specified, retrieves full detail for the run with this ID.
        If no matching artifact is found, a terminating error is thrown.

    .PARAMETER Last
        Number of most-recent runs to return in list mode. Defaults to 20.
        Ignored when -RunId is specified.

    .PARAMETER LogRoot
        Root directory containing OpenCodeLab run artifact files.
        Defaults to 'C:\LabSources\Logs'.

    .EXAMPLE
        Get-LabRunHistory
        Returns a summary table of the last 20 runs, sorted newest-first.

    .EXAMPLE
        Get-LabRunHistory -Last 5
        Returns a summary table of the 5 most recent runs.

    .EXAMPLE
        Get-LabRunHistory -RunId 'abc12345'
        Returns full detail for the run with ID 'abc12345'.

    .EXAMPLE
        Get-LabRunHistory -LogRoot 'D:\CustomLogs'
        Returns run history from a custom log directory.

    .OUTPUTS
        PSCustomObject[]
        In list mode: objects with RunId, Action, Mode, Success, DurationSeconds, EndedUtc, Error.
        In detail mode: full run object from JSON (run_id, action, dispatch_mode, events, etc.).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$RunId,
        [int]$Last = 20,
        [string]$LogRoot = 'C:\LabSources\Logs'
    )

    if ($PSBoundParameters.ContainsKey('RunId') -and -not [string]::IsNullOrWhiteSpace($RunId)) {
        # --- Detail mode: return full JSON for specified RunId ---
        $allPaths = @(Get-LabRunArtifactPaths -LogRoot $LogRoot)

        $matchingPaths = @($allPaths | Where-Object {
            [string]::Equals([System.IO.Path]::GetExtension($_), '.json', [System.StringComparison]::OrdinalIgnoreCase) -and
            $_ -like "*$RunId*"
        })

        if ($matchingPaths.Count -eq 0) {
            throw "Run '$RunId' not found in '$LogRoot'"
        }

        $artifactPath = $matchingPaths[0]

        try {
            $fullData = Get-Content -Raw -Path $artifactPath | ConvertFrom-Json
        }
        catch {
            throw "Failed to read run artifact '$artifactPath': $($_.Exception.Message)"
        }

        return $fullData
    }
    else {
        # --- List mode: return summary of last N runs ---
        $allPaths = @(Get-LabRunArtifactPaths -LogRoot $LogRoot)

        $jsonPaths = @($allPaths | Where-Object {
            [string]::Equals([System.IO.Path]::GetExtension($_), '.json', [System.StringComparison]::OrdinalIgnoreCase)
        })

        $summaries = New-Object System.Collections.Generic.List[PSCustomObject]

        foreach ($path in $jsonPaths) {
            try {
                $summary = Get-LabRunArtifactSummary -ArtifactPath $path
                $entry = [pscustomobject]@{
                    RunId           = $summary.RunId
                    Action          = $summary.Action
                    Mode            = $summary.Mode
                    Success         = $summary.Success
                    DurationSeconds = $summary.DurationSeconds
                    EndedUtc        = $summary.EndedUtc
                    Error           = $summary.Error
                }
                $summaries.Add($entry)
            }
            catch {
                Write-Warning "Skipping corrupt or unreadable artifact '$path': $($_.Exception.Message)"
            }
        }

        $results = @($summaries |
            Sort-Object -Property @{ Expression = { $_.EndedUtc }; Descending = $true } |
            Select-Object -First $Last)

        return $results
    }
}
