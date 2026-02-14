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
        [string]$LogRoot = 'C:\LabSources\Logs',
        [datetime]$SinceUtc,
        [string[]]$ExcludeArtifactPaths = @()
    )

    if (-not (Test-Path -Path $LogRoot)) {
        return $null
    }

    $excludeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($excluded in $ExcludeArtifactPaths) {
        if ([string]::IsNullOrWhiteSpace($excluded)) {
            continue
        }

        try {
            $resolved = (Resolve-Path -Path $excluded -ErrorAction Stop).Path
            $excludeSet.Add($resolved) | Out-Null
        }
        catch {
            $excludeSet.Add([System.IO.Path]::GetFullPath($excluded)) | Out-Null
        }
    }

    $candidateFiles = @(Get-ChildItem -Path $LogRoot -Filter 'OpenCodeLab-Run-*' -File -ErrorAction SilentlyContinue |
        Where-Object {
            [string]::Equals($_.Extension, '.json', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($_.Extension, '.txt', [System.StringComparison]::OrdinalIgnoreCase)
        })

    if ($PSBoundParameters.ContainsKey('SinceUtc')) {
        $candidateFiles = @($candidateFiles | Where-Object { $_.LastWriteTimeUtc -ge $SinceUtc })
    }

    if ($excludeSet.Count -gt 0) {
        $candidateFiles = @($candidateFiles | Where-Object { -not $excludeSet.Contains($_.FullName) })
    }

    $latestArtifact = $candidateFiles |
        Sort-Object -Property @(
            @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true },
            @{ Expression = {
                    if ([string]::Equals($_.Extension, '.json', [System.StringComparison]::OrdinalIgnoreCase)) {
                        0
                    }
                    else {
                        1
                    }
                }; Descending = $false },
            @{ Expression = { $_.Name }; Descending = $true }
        ) |
        Select-Object -First 1

    if ($latestArtifact) {
        return $latestArtifact.FullName
    }

    return $null
}

function Get-LabRunArtifactPaths {
    [CmdletBinding()]
    param(
        [string]$LogRoot = 'C:\LabSources\Logs'
    )

    if (-not (Test-Path -Path $LogRoot)) {
        return @()
    }

    return @(Get-ChildItem -Path $LogRoot -Filter 'OpenCodeLab-Run-*' -File -ErrorAction SilentlyContinue |
        Where-Object {
            [string]::Equals($_.Extension, '.json', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($_.Extension, '.txt', [System.StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object { $_.FullName })
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
        try {
            $payload = Get-Content -Raw -Path $ArtifactPath | ConvertFrom-Json
        }
        catch {
            throw "Invalid run artifact JSON in '$ArtifactPath': $($_.Exception.Message)"
        }
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
