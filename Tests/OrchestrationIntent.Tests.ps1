# Resolve-LabOrchestrationIntent tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabOrchestrationIntent.ps1')
}

Describe 'Resolve-LabOrchestrationIntent' {
    It 'uses fast startup sequence for deploy quick' {
        $result = Resolve-LabOrchestrationIntent -Action 'deploy' -EffectiveMode 'quick'

        $result.Strategy | Should -Be 'deploy-quick'
        $result.RunDeployScript | Should -BeFalse
        $result.RunQuickStartupSequence | Should -BeTrue
        $result.RunQuickReset | Should -BeFalse
        $result.RunBlowAway | Should -BeFalse
    }

    It 'uses full deploy script for deploy full' {
        $result = Resolve-LabOrchestrationIntent -Action 'deploy' -EffectiveMode 'full'

        $result.Strategy | Should -Be 'deploy-full'
        $result.RunDeployScript | Should -BeTrue
        $result.RunQuickStartupSequence | Should -BeFalse
        $result.RunQuickReset | Should -BeFalse
        $result.RunBlowAway | Should -BeFalse
    }

    It 'uses non-destructive quick reset for teardown quick' {
        $result = Resolve-LabOrchestrationIntent -Action 'teardown' -EffectiveMode 'quick'

        $result.Strategy | Should -Be 'teardown-quick'
        $result.RunDeployScript | Should -BeFalse
        $result.RunQuickStartupSequence | Should -BeFalse
        $result.RunQuickReset | Should -BeTrue
        $result.RunBlowAway | Should -BeFalse
    }

    It 'uses destructive blow-away for teardown full' {
        $result = Resolve-LabOrchestrationIntent -Action 'teardown' -EffectiveMode 'full'

        $result.Strategy | Should -Be 'teardown-full'
        $result.RunDeployScript | Should -BeFalse
        $result.RunQuickStartupSequence | Should -BeFalse
        $result.RunQuickReset | Should -BeFalse
        $result.RunBlowAway | Should -BeTrue
    }
}
