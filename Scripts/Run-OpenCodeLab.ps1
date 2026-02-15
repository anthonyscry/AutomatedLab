# Run-OpenCodeLab.ps1 - lightweight build check + app launcher

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$NoLaunch,
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
        (Join-Path $repoRoot 'OpenCodeLab-GUI.ps1')
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

$effectiveArguments = @($AppArguments)
if ($effectiveArguments.Count -eq 0) {
    $effectiveArguments = @('-Action', 'menu')
}

& $appScriptPath @effectiveArguments
