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
