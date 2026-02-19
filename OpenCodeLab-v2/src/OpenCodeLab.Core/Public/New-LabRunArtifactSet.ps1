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

    $runPath = Join-Path -Path $LogRoot -ChildPath $RunId
    $null = New-Item -Path $runPath -ItemType Directory -Force

    $runFilePath = Join-Path -Path $runPath -ChildPath 'run.json'
    $eventsFilePath = Join-Path -Path $runPath -ChildPath 'events.jsonl'
    $summaryFilePath = Join-Path -Path $runPath -ChildPath 'summary.txt'

    '{}' | Set-Content -Path $runFilePath -Encoding utf8 -NoNewline
    '' | Set-Content -Path $eventsFilePath -Encoding utf8 -NoNewline
    '' | Set-Content -Path $summaryFilePath -Encoding utf8 -NoNewline

    return [pscustomobject][ordered]@{
        RunId = $RunId
        Path = $runPath
        RunFilePath = $runFilePath
        EventsFilePath = $eventsFilePath
        SummaryFilePath = $summaryFilePath
    }
}
