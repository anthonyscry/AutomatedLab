# Resolve-LabDispatchMode tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabDispatchMode.ps1')
}

Describe 'Resolve-LabDispatchMode' {
    BeforeEach {
        $script:originalDispatchModeEnv = $env:OPENCODELAB_DISPATCH_MODE
        Remove-Item Env:OPENCODELAB_DISPATCH_MODE -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:originalDispatchModeEnv) {
            Remove-Item Env:OPENCODELAB_DISPATCH_MODE -ErrorAction SilentlyContinue
        }
        else {
            $env:OPENCODELAB_DISPATCH_MODE = $script:originalDispatchModeEnv
        }
    }

    It 'defaults to off when neither parameter nor env var is provided' {
        $result = Resolve-LabDispatchMode

        $result.Mode | Should -Be 'off'
        $result.Source | Should -Be 'default'
        $result.ExecutionEnabled | Should -BeFalse
    }

    It 'uses explicit parameter value over environment value' {
        $env:OPENCODELAB_DISPATCH_MODE = 'canary'

        $result = Resolve-LabDispatchMode -Mode 'enforced'

        $result.Mode | Should -Be 'enforced'
        $result.Source | Should -Be 'parameter'
        $result.ExecutionEnabled | Should -BeTrue
    }

    It 'uses environment value when parameter is not provided' {
        $env:OPENCODELAB_DISPATCH_MODE = 'canary'

        $result = Resolve-LabDispatchMode

        $result.Mode | Should -Be 'canary'
        $result.Source | Should -Be 'environment'
        $result.ExecutionEnabled | Should -BeTrue
    }

    It 'normalizes environment value casing and whitespace' {
        $env:OPENCODELAB_DISPATCH_MODE = '  EnFoRcEd  '

        $result = Resolve-LabDispatchMode

        $result.Mode | Should -Be 'enforced'
        $result.Source | Should -Be 'environment'
        $result.ExecutionEnabled | Should -BeTrue
    }

    It 'rejects unsupported environment value' {
        $env:OPENCODELAB_DISPATCH_MODE = 'invalid'

        { Resolve-LabDispatchMode } | Should -Throw '*Unsupported dispatch mode*'
    }

    It 'rejects explicit empty mode and does not fall back to environment' {
        $env:OPENCODELAB_DISPATCH_MODE = 'canary'

        { Resolve-LabDispatchMode -Mode '   ' } | Should -Throw '*Mode cannot be empty*'
    }

    It 'rejects unsupported values' {
        { Resolve-LabDispatchMode -Mode 'invalid' } | Should -Throw '*Unsupported dispatch mode*'
    }
}
