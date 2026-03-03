[CmdletBinding()]
param(
    [switch]$SkipSmoke,
    [switch]$SkipVulnerabilityScan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-QualityGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Output "[gate] $Name"
    & $Action
    Write-Output "[pass] $Name"
    Write-Output ''
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$unitPath = Join-Path -Path $projectRoot -ChildPath 'tests/unit'
$integrationPath = Join-Path -Path $projectRoot -ChildPath 'tests/integration'
$smokePath = Join-Path -Path $projectRoot -ChildPath 'tests/smoke'
$srcPath = Join-Path -Path $projectRoot -ChildPath 'src'
$scriptsPath = Join-Path -Path $projectRoot -ChildPath 'scripts'
$projectFile = Join-Path -Path $projectRoot -ChildPath 'OpenCodeLab-V2.csproj'

Invoke-QualityGate -Name 'Unit tests' -Action {
    $config = New-PesterConfiguration
    $config.Run.Path = $unitPath
    $config.Run.Exit = $false
    $config.Run.PassThru = $true
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @("$srcPath/**/*.ps1", "$srcPath/**/*.psm1")
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = 'coverage-unit.xml'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) {
        throw "Unit tests failed ($($result.FailedCount))."
    }
}

Invoke-QualityGate -Name 'Code coverage threshold' -Action {
    if (Test-Path 'coverage-unit.xml') {
        [xml]$coverageXml = Get-Content 'coverage-unit.xml'
        $lineCounter = $coverageXml.report.counter | Where-Object { $_.type -eq 'LINE' }
        if ($lineCounter) {
            $linesCovered = [double]$lineCounter.covered
            $linesMissed = [double]$lineCounter.missed
            $linesTotal = $linesCovered + $linesMissed
            if ($linesTotal -gt 0) {
                $coveragePercent = ($linesCovered / $linesTotal) * 100
                Write-Output "Code coverage: $([Math]::Round($coveragePercent, 2))% ($([int]$linesCovered)/$([int]$linesTotal) lines)"
                if ($coveragePercent -lt 50) {
                    Write-Warning "Code coverage is below 50% threshold ($([Math]::Round($coveragePercent, 2))%)."
                }
            }
        } else {
            Write-Warning "No LINE counter found in coverage report."
        }
    } else {
        Write-Warning "Coverage report not found at coverage-unit.xml"
    }
}

Invoke-QualityGate -Name 'Integration tests' -Action {
    $config = New-PesterConfiguration
    $config.Run.Path = $integrationPath
    $config.Run.Exit = $false
    $config.Run.PassThru = $true
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0) {
        throw "Integration tests failed ($($result.FailedCount))."
    }
}

if (-not $SkipSmoke) {
    Invoke-QualityGate -Name 'Smoke tests' -Action {
        $config = New-PesterConfiguration
        $config.Run.Path = $smokePath
        $config.Run.Exit = $false
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'Detailed'
        $result = Invoke-Pester -Configuration $config
        if ($result.FailedCount -gt 0) {
            throw "Smoke tests failed ($($result.FailedCount))."
        }
    }
}

Invoke-QualityGate -Name 'ScriptAnalyzer (errors block, warnings report)' -Action {
    $warnings = @()
    $warnings += @(Invoke-ScriptAnalyzer -Path $srcPath -Recurse -Severity Warning)
    $warnings += @(Invoke-ScriptAnalyzer -Path $scriptsPath -Recurse -Severity Warning)

    if ($warnings.Count -gt 0) {
        Write-Warning "ScriptAnalyzer reported $($warnings.Count) warning issue(s)."
        $warnings | Format-Table -AutoSize
    }

    $errors = @()
    $errors += @(Invoke-ScriptAnalyzer -Path $srcPath -Recurse -Severity Error)
    $errors += @(Invoke-ScriptAnalyzer -Path $scriptsPath -Recurse -Severity Error)

    if ($errors.Count -gt 0) {
        $errors | Format-Table -AutoSize
        throw "ScriptAnalyzer reported $($errors.Count) error issue(s)."
    }
}

Invoke-QualityGate -Name 'Build WPF application' -Action {
    & dotnet build $projectFile -c Release --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE."
    }
}

if (-not $SkipVulnerabilityScan) {
    Invoke-QualityGate -Name '.NET dependency vulnerability scan' -Action {
        $output = (& dotnet list $projectFile package --vulnerable --include-transitive | Out-String)
        Write-Output $output.TrimEnd()
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet list package --vulnerable failed with exit code $LASTEXITCODE."
        }

        if ($output -notmatch 'has no vulnerable packages') {
            throw 'Potential vulnerable packages detected. Review output above.'
        }
    }
}

Write-Output '[ready] Ship-readiness gates passed.'
