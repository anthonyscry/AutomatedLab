# /run alias and launcher script tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $runScriptPath = Join-Path $repoRoot 'Scripts/Run-OpenCodeLab.ps1'
    $runCommandPath = Join-Path $repoRoot '.opencode/commands/run.md'
}

Describe 'OpenCodeLab /run alias' {
    It 'defines an OpenCode command alias for /run' {
        (Test-Path -Path $runCommandPath) | Should -BeTrue

        $commandText = Get-Content -Raw -Path $runCommandPath
        $commandText | Should -Match 'description:\s*Build and run OpenCodeLab app'
        $commandText | Should -Match 'disable-model-invocation:\s*true'
        $commandText | Should -Match 'Run-OpenCodeLab\.ps1'
        $commandText | Should -Match '\$ARGUMENTS'
    }

    It 'provides a run script with build and no-launch switches' {
        (Test-Path -Path $runScriptPath) | Should -BeTrue

        $runScriptText = Get-Content -Raw -Path $runScriptPath
        $runScriptText | Should -Match '\[switch\]\$SkipBuild'
        $runScriptText | Should -Match '\[switch\]\$NoLaunch'
    }

    It 'allows no-launch invocation for script-only checks' {
        & $runScriptPath -NoLaunch
    }
}
