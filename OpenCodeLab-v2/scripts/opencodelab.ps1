[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Command,

    [ValidateSet('full', 'quick')]
    [string]$Mode = 'full',

    [switch]$Force,

    [ValidateSet('text', 'json')]
    [string]$Output = 'text',

    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath '../config/lab.settings.psd1')
)

Set-StrictMode -Version Latest

function Resolve-LauncherLogRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $resolvedLogRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../artifacts/logs'))

    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        return $resolvedLogRoot
    }

    $config = Import-PowerShellDataFile -Path $ConfigPath
    if ($config -isnot [hashtable]) {
        return $resolvedLogRoot
    }

    $configuredLogRoot = [string]$config.Paths.LogRoot
    if ([string]::IsNullOrWhiteSpace($configuredLogRoot)) {
        return $resolvedLogRoot
    }

    $resolvedConfigPath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $ConfigPath).ProviderPath)
    $configDirectory = Split-Path -Path $resolvedConfigPath -Parent

    if ([System.IO.Path]::IsPathRooted($configuredLogRoot)) {
        return [System.IO.Path]::GetFullPath($configuredLogRoot)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $configDirectory -ChildPath $configuredLogRoot))
}

function New-LauncherFailureArtifactSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$Mode,

        [Parameter(Mandatory)]
        [psobject]$Result
    )

    $logRoot = Resolve-LauncherLogRoot -ConfigPath $ConfigPath
    $null = New-Item -Path $logRoot -ItemType Directory -Force
    $resolvedLogRoot = [System.IO.Path]::GetFullPath((Resolve-Path -Path $logRoot).ProviderPath)

    $runId = ([guid]::NewGuid()).ToString()
    $artifactPath = [System.IO.Path]::GetFullPath((Join-Path -Path $resolvedLogRoot -ChildPath $runId))
    $null = New-Item -Path $artifactPath -ItemType Directory -Force

    $runFilePath = Join-Path -Path $artifactPath -ChildPath 'run.json'
    $summaryFilePath = Join-Path -Path $artifactPath -ChildPath 'summary.txt'
    $errorsFilePath = Join-Path -Path $artifactPath -ChildPath 'errors.json'
    $eventsFilePath = Join-Path -Path $artifactPath -ChildPath 'events.jsonl'

    $Result.ArtifactPath = $artifactPath

    Set-Content -Path $runFilePath -Value ($Result | ConvertTo-Json -Depth 10) -Encoding utf8 -NoNewline
    Set-Content -Path $summaryFilePath -Value (@(
        "Action: $($Result.Action)",
        "Succeeded: $($Result.Succeeded)",
        "FailureCategory: $($Result.FailureCategory)",
        "ErrorCode: $($Result.ErrorCode)",
        "DurationMs: $($Result.DurationMs)",
        "ArtifactPath: $($Result.ArtifactPath)"
    ) -join [Environment]::NewLine) -Encoding utf8 -NoNewline
    Set-Content -Path $errorsFilePath -Value (@([ordered]@{
        ErrorCode = $Result.ErrorCode
        FailureCategory = $Result.FailureCategory
        RecoveryHint = $Result.RecoveryHint
    }) | ConvertTo-Json -Depth 10) -Encoding utf8 -NoNewline
    Set-Content -Path $eventsFilePath -Value (@(
        (@{ type = 'run-started'; action = $Result.Action; mode = $Mode } | ConvertTo-Json -Compress),
        (@{ type = 'run-finished'; succeeded = $false; failureCategory = $Result.FailureCategory; durationMs = $Result.DurationMs } | ConvertTo-Json -Compress)
    ) -join [Environment]::NewLine) -Encoding utf8 -NoNewline
}

$moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../src/OpenCodeLab.App/OpenCodeLab.App.psd1'

$result = $null
$exitCode = 4

try {
    Import-Module $moduleManifestPath -Force
    $result = Invoke-LabCliCommand -Command $Command -Mode $Mode -Force:$Force -ConfigPath $ConfigPath
    $exitCode = Resolve-LabExitCode -Result $result
}
catch {
    $isStartupOrImportFailure = ($_.Exception.Message -like 'StartupError:*') -or ($_.CategoryInfo.Activity -eq 'Import-Module')
    if (-not (Get-Command -Name Invoke-LabCliCommand -ErrorAction SilentlyContinue)) {
        $isStartupOrImportFailure = $true
    }

    $failureCategory = 'UnexpectedException'
    $errorCode = 'UNEXPECTED_EXCEPTION'
    if ($isStartupOrImportFailure) {
        $failureCategory = 'StartupError'
        $errorCode = 'STARTUP_FAILURE'
    }

    $result = [pscustomobject][ordered]@{
        Action          = $Command
        Succeeded       = $false
        FailureCategory = $failureCategory
        ErrorCode       = $errorCode
        RecoveryHint    = $_.Exception.Message
        DurationMs      = [int]0
        ArtifactPath    = $null
    }

    try {
        New-LauncherFailureArtifactSet -ConfigPath $ConfigPath -Mode $Mode -Result $result
    }
    catch {
    }

    if (Get-Command -Name Resolve-LabExitCode -ErrorAction SilentlyContinue) {
        $exitCode = Resolve-LabExitCode -Result $result
    }
    elseif ($isStartupOrImportFailure) {
        $exitCode = 3
    }
}

if ($Output -eq 'json') {
    Write-Output ($result | ConvertTo-Json -Depth 10)
}
else {
    Write-Output (@(
        "Action: $($result.Action)",
        "Succeeded: $($result.Succeeded)",
        "FailureCategory: $($result.FailureCategory)",
        "ErrorCode: $($result.ErrorCode)",
        "RecoveryHint: $($result.RecoveryHint)",
        "DurationMs: $($result.DurationMs)",
        "ArtifactPath: $($result.ArtifactPath)"
    ) -join [Environment]::NewLine)
}

exit $exitCode
