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

function Get-DefaultLauncherLogRoot {
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../artifacts/logs'))
}

function Resolve-LauncherLogRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $resolvedLogRoot = Get-DefaultLauncherLogRoot

    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        return $resolvedLogRoot
    }

    try {
        $config = Import-PowerShellDataFile -Path $ConfigPath -ErrorAction Stop
        if ($config -isnot [hashtable]) {
            return $resolvedLogRoot
        }

        $configuredLogRoot = [string]$config.Paths.LogRoot
        if ([string]::IsNullOrWhiteSpace($configuredLogRoot)) {
            return $resolvedLogRoot
        }

        $resolvedConfigPath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $ConfigPath -ErrorAction Stop).ProviderPath)
        $configDirectory = Split-Path -Path $resolvedConfigPath -Parent

        if ([System.IO.Path]::IsPathRooted($configuredLogRoot)) {
            return [System.IO.Path]::GetFullPath($configuredLogRoot)
        }

        return [System.IO.Path]::GetFullPath((Join-Path -Path $configDirectory -ChildPath $configuredLogRoot))
    }
    catch {
        return $resolvedLogRoot
    }
}

function New-LauncherFailureArtifactSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$Mode,

        [Parameter(Mandatory)]
        [psobject]$Result,

        [string]$LogRootOverride
    )

    $logRoot = if ([string]::IsNullOrWhiteSpace($LogRootOverride)) {
        Resolve-LauncherLogRoot -ConfigPath $ConfigPath
    }
    else {
        [System.IO.Path]::GetFullPath($LogRootOverride)
    }

    $null = New-Item -Path $logRoot -ItemType Directory -Force
    $resolvedLogRoot = [System.IO.Path]::GetFullPath((Resolve-Path -Path $logRoot -ErrorAction Stop).ProviderPath)

    $runId = [string]$Result.RunId
    if ([string]::IsNullOrWhiteSpace($runId)) {
        $runId = ([guid]::NewGuid()).ToString()
    }
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
    $runStartedTimestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $runFinishedTimestamp = [DateTimeOffset]::UtcNow.ToString('o')
    Set-Content -Path $eventsFilePath -Value (@(
        (@{ timestamp = $runStartedTimestamp; type = 'run-started'; action = $Result.Action; mode = $Mode } | ConvertTo-Json -Compress),
        (@{ timestamp = $runFinishedTimestamp; type = 'run-finished'; succeeded = $false; failureCategory = $Result.FailureCategory; durationMs = $Result.DurationMs } | ConvertTo-Json -Compress)
    ) -join [Environment]::NewLine) -Encoding utf8 -NoNewline
}

$moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../src/OpenCodeLab.App/OpenCodeLab.App.psd1'

$result = $null
$exitCode = 4

try {
    Import-Module $moduleManifestPath -Force -ErrorAction Stop
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
        RunId           = ([guid]::NewGuid()).ToString()
        Action          = $Command
        RequestedMode   = $Mode
        EffectiveMode   = $Mode
        PolicyOutcome   = 'Approved'
        Succeeded       = $false
        FailureCategory = $failureCategory
        ErrorCode       = $errorCode
        RecoveryHint    = $_.Exception.Message
        ArtifactPath    = $null
        DurationMs      = [int]0
    }

    $artifactMessages = @()
    try {
        New-LauncherFailureArtifactSet -ConfigPath $ConfigPath -Mode $Mode -Result $result
    }
    catch {
        $artifactMessages += "Primary artifact creation failed: $($_.Exception.Message)"

        try {
            New-LauncherFailureArtifactSet -ConfigPath $ConfigPath -Mode $Mode -Result $result -LogRootOverride (Get-DefaultLauncherLogRoot)
        }
        catch {
            $artifactMessages += "Fallback artifact creation failed: $($_.Exception.Message)"
        }
    }

    if ($artifactMessages.Count -gt 0) {
        $artifactHint = $artifactMessages -join ' '
        if ([string]::IsNullOrWhiteSpace($result.RecoveryHint)) {
            $result.RecoveryHint = $artifactHint
        }
        else {
            $result.RecoveryHint = "$($result.RecoveryHint) $artifactHint"
        }
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
