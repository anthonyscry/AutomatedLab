# Helpers-TestReport.ps1 -- Shared helpers for Health and Preflight test scripts
# Provides Add-Issue and Add-Ok functions for consistent test reporting.
# Usage: Dot-source this file and initialize $script:issues before use.
#   $script:issues = New-Object System.Collections.Generic.List[string]
#   . "$PSScriptRoot\Helpers-TestReport.ps1"

function Add-Issue {
    param([Parameter(Mandatory)][string]$Message)
    $script:issues.Add($Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Add-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}
