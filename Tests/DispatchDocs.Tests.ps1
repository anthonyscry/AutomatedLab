# Documentation coverage tests for dispatch rollout

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $readmePath = Join-Path $repoRoot 'README.md'
    $smokeChecklistPath = Join-Path $repoRoot 'docs/SMOKE-CHECKLIST.md'
    $architecturePath = Join-Path $repoRoot 'docs/ARCHITECTURE.md'
}

Describe 'Dispatch documentation coverage' {
    It 'README documents concrete dispatch mode examples, rollback kill switch, and execution outcomes' {
        $content = Get-Content -Path $readmePath -Raw

        $content | Should -Match 'DispatchMode'
        $content | Should -Match '(?i)off\|canary\|enforced'
        $content | Should -Match '(?m)^\.\\OpenCodeLab-App\.ps1 .* -DispatchMode canary .*NonInteractive$'
        $content | Should -Match '(?i)rollback note:'
        $content | Should -Match '(?i)kill switch'
        $content | Should -Match 'ExecutionOutcome'
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

    It 'smoke checklist documents dispatch gate suite verification commands' {
        $content = Get-Content -Path $smokeChecklistPath -Raw

        $content | Should -Match 'DispatchMode\.Tests\.ps1'
        $content | Should -Match 'CoordinatorDispatch\.Tests\.ps1'
        $content | Should -Match 'OpenCodeLabDispatchContract\.Tests\.ps1'
        $content | Should -Match 'Tests\\Run\.Tests\.ps1'
    }

    It 'architecture notes document dispatcher controls, failure policy, and execution outcome verification expectations' {
        $content = Get-Content -Path $architecturePath -Raw

        $content | Should -Match '(?i)dispatcher layer'
        $content | Should -Match '(?i)action-based failure policy'
        $content | Should -Match '(?is)dispatch controls are verified through\s+`ExecutionOutcome`.*off.*not_dispatched.*canary.*exactly one host.*enforced'
    }
}
