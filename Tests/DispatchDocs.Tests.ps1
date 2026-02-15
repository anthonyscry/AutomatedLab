# Documentation coverage tests for dispatch rollout

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $readmePath = Join-Path $repoRoot 'README.md'
    $smokeChecklistPath = Join-Path $repoRoot 'docs/SMOKE-CHECKLIST.md'
    $architecturePath = Join-Path $repoRoot 'docs/ARCHITECTURE.md'
}

Describe 'Dispatch documentation coverage' {
    It 'README documents concrete dispatch mode examples and rollback kill switch' {
        $content = Get-Content -Path $readmePath -Raw

        $content | Should -Match 'DispatchMode'
        $content | Should -Match '(?i)off\|canary\|enforced'
        $content | Should -Match '(?m)^\.\\OpenCodeLab-App\.ps1 .* -DispatchMode canary .*NonInteractive$'
        $content | Should -Match '(?i)rollback note:'
        $content | Should -Match '(?i)kill switch'
    }

    It 'README documents DispatchMode precedence over OPENCODELAB_DISPATCH_MODE' {
        $content = Get-Content -Path $readmePath -Raw

        $content | Should -Match 'OPENCODELAB_DISPATCH_MODE'
        $content | Should -Match '(?i)explicit\s+`-DispatchMode`\s+takes\s+precedence'
    }

    It 'smoke checklist includes canary semantics and execution outcomes' {
        Test-Path -Path $smokeChecklistPath | Should -BeTrue

        $content = Get-Content -Path $smokeChecklistPath -Raw
        $content | Should -Match 'DispatchMode'
        $content | Should -Match 'ExecutionOutcome'
        $content | Should -Match '(?i)exactly one host is dispatched'
        $content | Should -Match '(?i)all others are reported as `not_dispatched`'
    }

    It 'architecture notes document dispatcher layer and action-based failure policy' {
        $content = Get-Content -Path $architecturePath -Raw

        $content | Should -Match '(?i)dispatcher layer'
        $content | Should -Match '(?i)action-based failure policy'
    }
}
