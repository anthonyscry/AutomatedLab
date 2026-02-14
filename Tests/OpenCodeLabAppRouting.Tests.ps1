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
            [object]$State,

            [Parameter()]
            [string]$ProfilePath,

            [Parameter()]
            [string[]]$TargetHosts,

            [Parameter()]
            [string]$InventoryPath,

            [Parameter()]
            [string]$ConfirmationToken
        )

        $invokeSplat = @{
            Action = $Action
            Mode = $Mode
            NoExecute = $true
        }

        if ($null -ne $State) {
            $invokeSplat.NoExecuteStateJson = ($State | ConvertTo-Json -Depth 10 -Compress)
        }

        if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
            $invokeSplat.ProfilePath = $ProfilePath
        }

        if ($TargetHosts -and $TargetHosts.Count -gt 0) {
            $invokeSplat.TargetHosts = $TargetHosts
        }

        if (-not [string]::IsNullOrWhiteSpace($InventoryPath)) {
            $invokeSplat.InventoryPath = $InventoryPath
        }

        if (-not [string]::IsNullOrWhiteSpace($ConfirmationToken)) {
            $invokeSplat.ConfirmationToken = $ConfirmationToken
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

    It 'teardown quick chooses quick reset intent when policy approves' {
        $hostProbe = [pscustomobject]@{
            HostName = 'local'
            Reachable = $true
            Probe = [pscustomobject]@{
                LabRegistered = $true
                MissingVMs = @()
                LabReadyAvailable = $true
                SwitchPresent = $true
                NatPresent = $true
            }
            Failure = $null
        }

        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'quick' -State @($hostProbe)

        $result.OrchestrationAction | Should -Be 'teardown'
        $result.EffectiveMode | Should -Be 'quick'
        $result.PolicyOutcome | Should -Be 'Approved'
        $result.OrchestrationIntent.Strategy | Should -Be 'teardown-quick'
        $result.OrchestrationIntent.RunQuickReset | Should -BeTrue
        $result.OrchestrationIntent.RunBlowAway | Should -BeFalse
    }

    It 'teardown full chooses full teardown intent when scoped confirmation is supplied' {
        $hostProbe = [pscustomobject]@{
            HostName = 'local'
            Reachable = $true
            Probe = [pscustomobject]@{
                LabRegistered = $true
                MissingVMs = @()
                LabReadyAvailable = $true
                SwitchPresent = $true
                NatPresent = $true
            }
            Failure = $null
        }

        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'full' -State @($hostProbe) -ConfirmationToken 'token-123'

        $result.OrchestrationAction | Should -Be 'teardown'
        $result.EffectiveMode | Should -Be 'full'
        $result.PolicyOutcome | Should -Be 'Approved'
        $result.OrchestrationIntent.Strategy | Should -Be 'teardown-full'
        $result.OrchestrationIntent.RunQuickReset | Should -BeFalse
        $result.OrchestrationIntent.RunBlowAway | Should -BeTrue
    }

    It 'teardown quick returns escalation-required policy outcome without silent destructive escalation' {
        $hostProbe = [pscustomobject]@{
            HostName = 'local'
            Reachable = $true
            Probe = [pscustomobject]@{
                LabRegistered = $true
                MissingVMs = @()
                LabReadyAvailable = $false
                SwitchPresent = $true
                NatPresent = $true
            }
            Failure = $null
        }

        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'quick' -State @($hostProbe)

        $result.PolicyOutcome | Should -Be 'EscalationRequired'
        $result.PolicyReason | Should -Be 'quick_teardown_requires_full'
        $result.EffectiveMode | Should -Be 'full'
    }

    It 'teardown full returns policy blocked outcome when scoped confirmation is missing' {
        $hostProbe = [pscustomobject]@{
            HostName = 'local'
            Reachable = $true
            Probe = [pscustomobject]@{
                LabRegistered = $true
                MissingVMs = @()
                LabReadyAvailable = $true
                SwitchPresent = $true
                NatPresent = $true
            }
            Failure = $null
        }

        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'full' -State @($hostProbe)

        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.PolicyReason | Should -Be 'missing_scoped_confirmation'
        $result.EffectiveMode | Should -Be 'full'
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

    It 'deploy quick safety fallback cannot be weakened by profile mode quick override' {
        $state = [pscustomobject]@{
            LabRegistered = $false
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }
        $profilePath = Join-Path $TestDrive 'unsafe-profile.json'
        '{"Mode":"quick"}' | Set-Content -Path $profilePath -Encoding UTF8

        $result = Invoke-AppNoExecute -Action 'deploy' -Mode 'quick' -State $state -ProfilePath $profilePath

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'lab_not_registered'
    }

    It 'deploy quick allows stricter profile override to full mode' {
        $state = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }
        $profilePath = Join-Path $TestDrive 'strict-profile.json'
        '{"Mode":"full"}' | Set-Content -Path $profilePath -Encoding UTF8

        $result = Invoke-AppNoExecute -Action 'deploy' -Mode 'quick' -State $state -ProfilePath $profilePath

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'profile_mode_override'
    }
}
