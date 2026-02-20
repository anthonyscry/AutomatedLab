Set-StrictMode -Version Latest

function New-LabRunArtifactSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    $null = New-Item -Path $LogRoot -ItemType Directory -Force

    $logRootPath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $LogRoot).ProviderPath)
    $runPath = [System.IO.Path]::GetFullPath((Join-Path -Path $logRootPath -ChildPath $RunId))

    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    $logRootPrefix = $logRootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $runPath.StartsWith($logRootPrefix, $comparison)) {
        throw 'RunId must resolve within LogRoot'
    }

    $null = New-Item -Path $runPath -ItemType Directory -Force

    $runFilePath = Join-Path -Path $runPath -ChildPath 'run.json'
    $eventsFilePath = Join-Path -Path $runPath -ChildPath 'events.jsonl'
    $summaryFilePath = Join-Path -Path $runPath -ChildPath 'summary.txt'
    $errorsFilePath = Join-Path -Path $runPath -ChildPath 'errors.json'

    '{}' | Set-Content -Path $runFilePath -Encoding utf8 -NoNewline
    '' | Set-Content -Path $eventsFilePath -Encoding utf8 -NoNewline
    '' | Set-Content -Path $summaryFilePath -Encoding utf8 -NoNewline
    '{}' | Set-Content -Path $errorsFilePath -Encoding utf8 -NoNewline

    return [pscustomobject][ordered]@{
        RunId = $RunId
        Path = $runPath
        RunFilePath = $runFilePath
        EventsFilePath = $eventsFilePath
        SummaryFilePath = $summaryFilePath
        ErrorsFilePath = $errorsFilePath
    }
}
