function New-LabGuiCommandPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppScriptPath,

        [hashtable]$Options
    )

    $argList = New-LabAppArgumentList -Options $Options
    $scriptLeaf = Split-Path -Leaf $AppScriptPath
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add(".\\$scriptLeaf") | Out-Null

    foreach ($token in $argList) {
        if ($token -match '^[A-Za-z0-9_\-./]+$') {
            $parts.Add($token) | Out-Null
            continue
        }

        $escaped = [string]$token -replace "'", "''"
        $parts.Add("'$escaped'") | Out-Null
    }

    return ($parts -join ' ')
}

function Get-LabLatestRunArtifactPath {
    [CmdletBinding()]
    param(
        [string]$LogRoot = 'C:\LabSources\Logs'
    )

    if (-not (Test-Path -Path $LogRoot)) {
        return $null
    }

    $latestJson = Get-ChildItem -Path $LogRoot -Filter 'OpenCodeLab-Run-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestJson) {
        return $latestJson.FullName
    }

    $latestTxt = Get-ChildItem -Path $LogRoot -Filter 'OpenCodeLab-Run-*.txt' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestTxt) {
        return $latestTxt.FullName
    }

    return $null
}

function Get-LabRunArtifactSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArtifactPath
    )

    if (-not (Test-Path -Path $ArtifactPath)) {
        throw "Artifact not found: $ArtifactPath"
    }

    $isJson = [string]::Equals([System.IO.Path]::GetExtension($ArtifactPath), '.json', [System.StringComparison]::OrdinalIgnoreCase)

    $runId = ''
    $action = ''
    $mode = ''
    $success = $false
    $durationSeconds = $null
    $endedUtc = ''
    $errorText = ''

    if ($isJson) {
        $payload = Get-Content -Raw -Path $ArtifactPath | ConvertFrom-Json
        $runId = [string]$payload.run_id
        $action = [string]$payload.action
        $mode = [string]$payload.effective_mode
        $success = [bool]$payload.success
        $durationSeconds = $payload.duration_seconds
        $endedUtc = [string]$payload.ended_utc
        $errorText = [string]$payload.error
    }
    else {
        $lineMap = @{}
        foreach ($line in (Get-Content -Path $ArtifactPath)) {
            if ($line -match '^\s*([A-Za-z0-9_\-]+)\s*:\s*(.*)$') {
                $lineMap[$matches[1]] = $matches[2]
            }
        }

        $runId = [string]$lineMap['run_id']
        $action = [string]$lineMap['action']
        $mode = [string]$lineMap['effective_mode']
        $endedUtc = [string]$lineMap['ended_utc']
        $errorText = [string]$lineMap['error']

        $successValue = [string]$lineMap['success']
        $success = $successValue -match '^(?i:true|1|yes)$'

        $durationValue = [string]$lineMap['duration_seconds']
        if (-not [string]::IsNullOrWhiteSpace($durationValue)) {
            $durationParsed = 0
            if ([int]::TryParse($durationValue, [ref]$durationParsed)) {
                $durationSeconds = $durationParsed
            }
        }
    }

    $stateText = if ($success) { 'SUCCESS' } else { 'FAILED' }
    $durationText = if ($null -eq $durationSeconds) { 'n/a' } else { "${durationSeconds}s" }
    $summaryText = "[$stateText] Action=$action Mode=$mode Duration=$durationText RunId=$runId"
    if (-not [string]::IsNullOrWhiteSpace($errorText)) {
        $summaryText = "$summaryText Error=$errorText"
    }

    return [pscustomobject]@{
        Path = $ArtifactPath
        RunId = $runId
        Action = $action
        Mode = $mode
        Success = $success
        DurationSeconds = $durationSeconds
        EndedUtc = $endedUtc
        Error = $errorText
        SummaryText = $summaryText
    }
}
