# Documentation coverage tests for dispatch rollout

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $readmePath = Join-Path $repoRoot 'README.md'
    $smokeChecklistPath = Join-Path $repoRoot 'docs/SMOKE-CHECKLIST.md'
}

Describe 'Dispatch documentation coverage' {
    It 'README documents dispatch mode controls' {
        $content = Get-Content -Path $readmePath -Raw

        $content | Should -Match 'DispatchMode'
        $content | Should -Match '(?i)off\|canary\|enforced'
    }

    It 'smoke checklist includes DispatchMode and ExecutionOutcome verification' {
        Test-Path -Path $smokeChecklistPath | Should -BeTrue

        $content = Get-Content -Path $smokeChecklistPath -Raw
        $content | Should -Match 'DispatchMode'
        $content | Should -Match 'ExecutionOutcome'
    }
}
