#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$InstallModule,
    [switch]$IncludeConfigNoise,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    if (-not $InstallModule) {
        throw "PSScriptAnalyzer is not installed. Re-run with -InstallModule to install it for CurrentUser."
    }

    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber
}

$allResults = @(Invoke-ScriptAnalyzer -Path $scriptRoot -Recurse -Severity Warning,Error)

$gateRules = @(
    'PSAvoidAssignmentToAutomaticVariable',
    'PSUseDeclaredVarsMoreThanAssignments'
)

if ($Full) {
    $results = @($allResults)
} else {
    $results = @($allResults | Where-Object { $_.RuleName -in $gateRules })
}

if (-not $IncludeConfigNoise) {
    $results = $results | Where-Object {
        -not (
            $_.RuleName -eq 'PSUseDeclaredVarsMoreThanAssignments' -and
            $_.ScriptName -eq 'Lab-Config.ps1'
        )
    }
}

if (-not $results -or $results.Count -eq 0) {
    if ($Full) {
        Write-Host "PSScriptAnalyzer full scan: clean (after configured noise filtering)." -ForegroundColor Green
    } else {
        Write-Host "PSScriptAnalyzer CI gate passed (rules: $($gateRules -join ', '))." -ForegroundColor Green
        Write-Host "  Full scan findings currently present (not CI-blocking): $($allResults.Count)" -ForegroundColor DarkGray
    }
    exit 0
}

if (-not $Full) {
    Write-Host "PSScriptAnalyzer mode: CI gate" -ForegroundColor Cyan
    Write-Host "  Gated rules: $($gateRules -join ', ')" -ForegroundColor DarkGray
    Write-Host "  Full scan findings currently present: $($allResults.Count)" -ForegroundColor DarkGray
}

Write-Host "PSScriptAnalyzer findings: $($results.Count)" -ForegroundColor Yellow
$results |
    Group-Object RuleName |
    Sort-Object Count -Descending |
    Format-Table Count, Name -AutoSize

Write-Host "`nTop findings:" -ForegroundColor Yellow
$results |
    Sort-Object Severity, RuleName, ScriptName, Line |
    Select-Object -First 40 Severity, RuleName, ScriptName, Line, Message |
    Format-Table -Wrap -AutoSize

exit 1
