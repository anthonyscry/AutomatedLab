# Resolve-LabDispatchPlan tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabDispatchPlan.ps1')
}

Describe 'Resolve-LabDispatchPlan' {
    It 'preserves setup action routing and forces full mode' {
        $result = Resolve-LabDispatchPlan -Action 'setup' -Mode 'quick'

        $result.DispatchAction | Should -Be 'setup'
        $result.OrchestrationAction | Should -BeNullOrEmpty
        $result.Mode | Should -Be 'full'
    }

    It 'preserves one-button-setup routing and forces full mode' {
        $result = Resolve-LabDispatchPlan -Action 'one-button-setup' -Mode 'quick'

        $result.DispatchAction | Should -Be 'one-button-setup'
        $result.OrchestrationAction | Should -BeNullOrEmpty
        $result.Mode | Should -Be 'full'
    }

    It 'preserves one-button-reset routing and forces full mode' {
        $result = Resolve-LabDispatchPlan -Action 'one-button-reset' -Mode 'quick'

        $result.DispatchAction | Should -Be 'one-button-reset'
        $result.OrchestrationAction | Should -BeNullOrEmpty
        $result.Mode | Should -Be 'full'
    }

    It 'keeps canonical deploy routing' {
        $result = Resolve-LabDispatchPlan -Action 'deploy' -Mode 'quick'

        $result.DispatchAction | Should -Be 'deploy'
        $result.OrchestrationAction | Should -Be 'deploy'
        $result.Mode | Should -Be 'quick'
    }

    It 'keeps canonical teardown routing' {
        $result = Resolve-LabDispatchPlan -Action 'teardown' -Mode 'full'

        $result.DispatchAction | Should -Be 'teardown'
        $result.OrchestrationAction | Should -Be 'teardown'
        $result.Mode | Should -Be 'full'
    }

    It 'keeps blow-away routing and forces full mode' {
        $result = Resolve-LabDispatchPlan -Action 'blow-away' -Mode 'quick'

        $result.DispatchAction | Should -Be 'blow-away'
        $result.OrchestrationAction | Should -BeNullOrEmpty
        $result.Mode | Should -Be 'full'
    }
}
