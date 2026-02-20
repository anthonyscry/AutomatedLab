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

Import-Module $moduleManifestPath -Force

$result = Invoke-LabCliCommand -Command $Command -Mode $Mode -Force:$Force -ConfigPath $ConfigPath
$global:LASTEXITCODE = Resolve-LabExitCode -Result $result

if ($Output -eq 'json') {
    return ($result | ConvertTo-Json -Depth 10)
}

@(
    "Action: $($result.Action)",
    "Succeeded: $($result.Succeeded)",
    "FailureCategory: $($result.FailureCategory)",
    "ErrorCode: $($result.ErrorCode)",
    "RecoveryHint: $($result.RecoveryHint)",
    "DurationMs: $($result.DurationMs)",
    "ArtifactPath: $($result.ArtifactPath)"
) -join [Environment]::NewLine
