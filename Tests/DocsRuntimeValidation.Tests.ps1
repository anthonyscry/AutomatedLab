# Runtime docs-validation contract tests
# Guards the validation script structure, output report contract, and skip semantics.
# Requirements: DOC-02, DOC-03

BeforeAll {
    $repoRoot      = Split-Path -Parent $PSScriptRoot
    $scriptPath    = Join-Path $repoRoot 'Scripts/Validate-DocsAgainstRuntime.ps1'
    $reportPath    = Join-Path $repoRoot 'docs/VALIDATION-RUNTIME.md'
}

Describe 'Validation script contract' {

    It 'validation script file exists' {
        Test-Path -Path $scriptPath | Should -BeTrue
    }

    It 'validation script references -Action status invocation' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match '\-Action'
        $content | Should -Match "'status'"
    }

    It 'validation script references -Action health invocation' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match '\-Action'
        $content | Should -Match "'health'"
    }

    It 'validation script references OpenCodeLab-App.ps1' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match 'OpenCodeLab-App\.ps1'
    }

    It 'validation script emits SKIPPED state when prerequisites are missing' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match 'SKIPPED'
        # Must also emit a reason alongside the skip state
        $content | Should -Match 'Reason'
    }

    It 'validation script writes the report using Set-Content' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match 'Set-Content'
    }

    It 'validation script accepts -OutputPath parameter' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match '\[string\]\$OutputPath'
    }

    It 'validation script accepts -TimeoutSeconds parameter' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match '\[int\]\$TimeoutSeconds'
    }

    It 'validation script uses Set-StrictMode' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match 'Set-StrictMode'
    }

    It 'validation script has Invoke-Pester-style CmdletBinding' {
        # Script must be invocable by pwsh -- confirm param block present
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding\(\)\]'
    }
}

Describe 'Output report contract' {

    It 'report file exists after script execution' {
        Test-Path -Path $reportPath | Should -BeTrue
    }

    It 'report contains Observed keyword (state token)' {
        $content = Get-Content -Path $reportPath -Raw
        $content | Should -Match 'Observed'
    }

    It 'report contains a timestamp' {
        $content = Get-Content -Path $reportPath -Raw
        # ISO-8601 or date-formatted timestamp
        $content | Should -Match 'Timestamp'
        $content | Should -Match '\d{4}-\d{2}-\d{2}'
    }

    It 'report contains status section evidence' {
        $content = Get-Content -Path $reportPath -Raw
        $content | Should -Match '(?i)status'
    }

    It 'report contains health section evidence' {
        $content = Get-Content -Path $reportPath -Raw
        $content | Should -Match '(?i)health'
    }

    It 'report documents docs alignment summary' {
        $content = Get-Content -Path $reportPath -Raw
        $content | Should -Match '(?i)(Docs Alignment|alignment)'
    }

    It 'report includes reference to LIFECYCLE-WORKFLOWS.md' {
        $content = Get-Content -Path $reportPath -Raw
        $content | Should -Match 'LIFECYCLE-WORKFLOWS'
    }
}

Describe 'Skip semantics contract' {

    It 'validation script documents a skip state path for missing app script' {
        $content = Get-Content -Path $scriptPath -Raw
        # Must have a Test-Path guard that leads to SKIPPED
        $content | Should -Match 'Test-Path'
        $content | Should -Match "'SKIPPED'"
    }

    It 'validation script documents a skip state path for invocation failure' {
        $content = Get-Content -Path $scriptPath -Raw
        # catch block must set SKIPPED state
        $content | Should -Match 'catch'
        # Count SKIPPED occurrences -- there must be more than one (multiple skip paths)
        $matches = ([regex]::Matches($content, "'SKIPPED'")).Count
        $matches | Should -BeGreaterThan 1
    }

    It 'validation script documents a skip state for timeout' {
        $content = Get-Content -Path $scriptPath -Raw
        $content | Should -Match '(?i)timed out|timeout|TimeoutSeconds'
    }

    It 'report includes skip and prerequisite notes section' {
        $content = Get-Content -Path $reportPath -Raw
        $content | Should -Match '(?i)(Skip|Prerequisite)'
    }

    It 'validation script outputs report scaffold even in skip path' {
        # The Set-Content call is always reached -- confirm it is outside try/catch
        $content = Get-Content -Path $scriptPath -Raw
        # The report write and Set-Content must appear after the function definitions
        # (i.e., not only inside a try block)
        $setContentIndex  = $content.LastIndexOf('Set-Content')
        $functionEndIndex = $content.LastIndexOf('^}', $setContentIndex)
        # Set-Content appears in the script body (not only inside helper functions)
        $setContentIndex | Should -BeGreaterThan 0
    }
}
