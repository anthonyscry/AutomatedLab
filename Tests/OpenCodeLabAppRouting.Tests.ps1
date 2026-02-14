# OpenCodeLab-App routing integration tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $appPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'

    function Invoke-AppNoExecute {
        param(
            [Parameter(Mandatory)]
            [string]$Action,

            [Parameter()]
            [ValidateSet('quick', 'full')]
            [string]$Mode = 'full',

            [Parameter()]
            [pscustomobject]$State
        )

        $invokeSplat = @{
            Action = $Action
            Mode = $Mode
            NoExecute = $true
        }

        if ($null -ne $State) {
            $invokeSplat.NoExecuteStateJson = ($State | ConvertTo-Json -Depth 10 -Compress)
        }

        & $appPath @invokeSplat
    }
}

Describe 'OpenCodeLab-App -NoExecute routing integration' {
    It 'setup quick preserves setup dispatch legacy path' {
        $result = Invoke-AppNoExecute -Action 'setup' -Mode 'quick'

        $result.DispatchAction | Should -Be 'setup'
        $result.OrchestrationAction | Should -BeNullOrEmpty
        $result.RequestedMode | Should -Be 'full'
    }

    It 'one-button-reset quick preserves one-button-reset dispatch legacy path' {
        $result = Invoke-AppNoExecute -Action 'one-button-reset' -Mode 'quick'

        $result.DispatchAction | Should -Be 'one-button-reset'
        $result.OrchestrationAction | Should -BeNullOrEmpty
        $result.RequestedMode | Should -Be 'full'
    }

    It 'teardown quick chooses quick reset intent' {
        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'quick'

        $result.OrchestrationAction | Should -Be 'teardown'
        $result.EffectiveMode | Should -Be 'quick'
        $result.OrchestrationIntent.Strategy | Should -Be 'teardown-quick'
        $result.OrchestrationIntent.RunQuickReset | Should -BeTrue
        $result.OrchestrationIntent.RunBlowAway | Should -BeFalse
    }

    It 'teardown full chooses full teardown intent' {
        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'full'

        $result.OrchestrationAction | Should -Be 'teardown'
        $result.EffectiveMode | Should -Be 'full'
        $result.OrchestrationIntent.Strategy | Should -Be 'teardown-full'
        $result.OrchestrationIntent.RunQuickReset | Should -BeFalse
        $result.OrchestrationIntent.RunBlowAway | Should -BeTrue
    }

    It 'deploy quick chooses quick deploy intent with reusable injected state' {
        $state = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-AppNoExecute -Action 'deploy' -Mode 'quick' -State $state

        $result.OrchestrationAction | Should -Be 'deploy'
        $result.EffectiveMode | Should -Be 'quick'
        $result.FallbackReason | Should -BeNullOrEmpty
        $result.OrchestrationIntent.Strategy | Should -Be 'deploy-quick'
        $result.OrchestrationIntent.RunQuickStartupSequence | Should -BeTrue
        $result.OrchestrationIntent.RunDeployScript | Should -BeFalse
    }
}
