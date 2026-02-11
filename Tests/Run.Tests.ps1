# SimpleLab Test Runner
# Run all Pester tests for the SimpleLab module

param(
    [Parameter()]
    [string]$OutputPath = (Join-Path $PSScriptRoot "TestResults.xml"),

    [Parameter()]
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Normal'
)

# Ensure Pester is available
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Warning "Pester module not found. Installing Pester..."
    Install-Module -Name Pester -Force -Scope CurrentUser -SkipPublisherCheck
}

# Import Pester
Import-Module Pester -MinimumVersion 5.0

# Get the module root
$moduleRoot = $PSScriptRoot | Split-Path

# Configure Pester
$config = New-PesterConfiguration

# Set output paths
$config.Run.Path = $PSScriptRoot
$config.Output.Verbosity = $Verbosity
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = $OutputPath

# Set code coverage
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = (Join-Path $moduleRoot "Public\*.ps1"), (Join-Path $moduleRoot "Private\*.ps1")
$config.CodeCoverage.OutputPath = (Join-Path $PSScriptRoot "coverage.xml")
$config.CodeCoverage.OutputFormat = 'JaCoCo'

# Display settings
$config.Output.CIFormat = 'Auto'

Write-Host "Running SimpleLab tests..." -ForegroundColor Cyan
Write-Host "Module Root: $moduleRoot" -ForegroundColor Gray

# Run tests
$result = Invoke-Pester -Configuration $config

# Exit with appropriate code
exit $result.FailedCount
