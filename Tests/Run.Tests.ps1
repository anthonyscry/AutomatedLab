# SimpleLab Test Runner
# Run all Pester tests for the SimpleLab module

param(
    [Parameter()]
    [string]$OutputPath,

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

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "TestResults.xml"
}

# Configure Pester
$config = New-PesterConfiguration

# Set output paths
$testFiles = @(
    Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'Run.Tests.ps1' } |
    Select-Object -ExpandProperty FullName
)
$config.Run.Path = $testFiles
$config.Output.Verbosity = $Verbosity
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = $OutputPath

# Set code coverage
$config.CodeCoverage.Enabled = $true
$publicCoveragePaths = @(
    Get-ChildItem -Path (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
)
$privateCoveragePaths = @(
    Get-ChildItem -Path (Join-Path $moduleRoot 'Private') -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName
)
$config.CodeCoverage.Path = @($publicCoveragePaths + $privateCoveragePaths)
$config.CodeCoverage.OutputPath = (Join-Path $PSScriptRoot "coverage.xml")
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.CoveragePercentTarget = 15

# Display settings — use GitHub Actions format when running in CI
if ($env:GITHUB_ACTIONS) {
    $config.Output.CIFormat = 'GithubActions'
} else {
    $config.Output.CIFormat = 'Auto'
}

# Ensure output directory exists
$resultsDir = Split-Path $OutputPath
if ($resultsDir -and -not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

Write-Host "Running SimpleLab tests..." -ForegroundColor Cyan
Write-Host "Module Root: $moduleRoot" -ForegroundColor Gray

# Run tests
$result = Invoke-Pester -Configuration $config

# Exit with appropriate code
exit $result.FailedCount
