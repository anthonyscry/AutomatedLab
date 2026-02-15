# Contract tests for execution metadata persistence

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $appPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'
    $scriptContent = Get-Content -Raw -Path $appPath
}

Describe 'OpenCodeLab dispatch execution metadata contract' {
    It 'includes additive execution metadata keys in JSON run artifacts' {
        $scriptContent | Should -Match 'dispatch_mode\s*='
        $scriptContent | Should -Match 'execution_outcome\s*='
        $scriptContent | Should -Match 'execution_started_at\s*='
        $scriptContent | Should -Match 'execution_completed_at\s*='
    }

    It 'includes additive execution metadata keys in text run summaries' {
        $scriptContent | Should -Match 'dispatch_mode:'
        $scriptContent | Should -Match 'execution_outcome:'
        $scriptContent | Should -Match 'execution_started_at:'
        $scriptContent | Should -Match 'execution_completed_at:'
    }
}
