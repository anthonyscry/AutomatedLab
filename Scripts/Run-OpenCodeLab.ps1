# Run-OpenCodeLab.ps1 - lightweight build check + app launcher

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$NoLaunch,
    [switch]$GUI,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PowerShellScriptSyntax {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message })
        throw "Syntax validation failed for '$Path': $($messages -join '; ')"
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptDir
$appScriptPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'

if (-not (Test-Path -Path $appScriptPath -PathType Leaf)) {
    throw "OpenCodeLab-App.ps1 not found at path: $appScriptPath"
}

if (-not $SkipBuild) {
    $buildTargets = @(
        $appScriptPath,
        (Join-Path $repoRoot 'Bootstrap.ps1'),
        (Join-Path $repoRoot 'Deploy.ps1'),
        (Join-Path $repoRoot 'OpenCodeLab-GUI.ps1'),
        (Join-Path (Join-Path $repoRoot 'GUI') 'Start-OpenCodeLabGUI.ps1')
    )

    foreach ($target in $buildTargets) {
        if (Test-Path -Path $target -PathType Leaf) {
            Test-PowerShellScriptSyntax -Path $target
        }
    }
}

if ($NoLaunch) {
    return
}

if ($GUI) {
    $guiScriptPath = Join-Path (Join-Path $repoRoot 'GUI') 'Start-OpenCodeLabGUI.ps1'
    if (-not (Test-Path -Path $guiScriptPath -PathType Leaf)) {
        throw "GUI entry point not found at path: $guiScriptPath"
    }
    & $guiScriptPath
    return
}

$effectiveArguments = @($AppArguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($effectiveArguments.Count -eq 0 -or ($effectiveArguments.Count -eq 1 -and $effectiveArguments[0] -eq '-Action')) {
    $effectiveArguments = @('menu')
}

& $appScriptPath @effectiveArguments
