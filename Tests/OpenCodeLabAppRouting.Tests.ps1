# OpenCodeLab-App routing integration tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $appPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'
    . (Join-Path $repoRoot 'Private/New-LabScopedConfirmationToken.ps1')

    $script:originalConfirmationRunId = $env:OPENCODELAB_CONFIRMATION_RUN_ID
    $script:originalConfirmationSecret = $env:OPENCODELAB_CONFIRMATION_SECRET
    $env:OPENCODELAB_CONFIRMATION_RUN_ID = 'tdd-run-scope-routing'
    $env:OPENCODELAB_CONFIRMATION_SECRET = 'tdd-secret-routing'

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

AfterAll {
    if ($null -eq $script:originalConfirmationRunId) {
        Remove-Item Env:OPENCODELAB_CONFIRMATION_RUN_ID -ErrorAction SilentlyContinue
    }
    else {
        $env:OPENCODELAB_CONFIRMATION_RUN_ID = $script:originalConfirmationRunId
    }

    if ($null -eq $script:originalConfirmationSecret) {
        Remove-Item Env:OPENCODELAB_CONFIRMATION_SECRET -ErrorAction SilentlyContinue
    }
    else {
        $env:OPENCODELAB_CONFIRMATION_SECRET = $script:originalConfirmationSecret
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

        $token = New-LabScopedConfirmationToken -RunId 'tdd-run-scope-routing' -TargetHosts @([Environment]::MachineName) -OperationHash 'teardown:full:teardown' -Secret 'tdd-secret-routing' -TtlSeconds 300
        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'full' -State @($hostProbe) -ConfirmationToken $token

        $result.OrchestrationAction | Should -Be 'teardown'
        $result.EffectiveMode | Should -Be 'full'
        $result.PolicyOutcome | Should -Be 'Approved'
        $result.OrchestrationIntent.Strategy | Should -Be 'teardown-full'
        $result.OrchestrationIntent.RunQuickReset | Should -BeFalse
        $result.OrchestrationIntent.RunBlowAway | Should -BeTrue
    }

    It 'teardown full rejects invalid scoped confirmation token and surfaces validator reason' {
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

        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'full' -State @($hostProbe) -ConfirmationToken 'not-a-valid-token'

        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.PolicyReason | Should -Be 'scoped_confirmation_invalid:malformed_token'
        $result.EffectiveMode | Should -Be 'full'
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

    It 'teardown quick with profile full override is policy blocked without scoped confirmation' {
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
        $profilePath = Join-Path $TestDrive 'teardown-profile-full.json'
        '{"Mode":"full"}' | Set-Content -Path $profilePath -Encoding UTF8

        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'quick' -State @($hostProbe) -ProfilePath $profilePath

        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.PolicyReason | Should -Be 'missing_scoped_confirmation'
        $result.EffectiveMode | Should -Be 'full'
    }

    It 'routing payload includes coordinator policy and host routing metadata' {
        $targetHost = [Environment]::MachineName
        $hostProbeA = [pscustomobject]@{
            HostName = $targetHost
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
        $hostProbeB = [pscustomobject]@{
            HostName = 'ignored-host'
            Reachable = $false
            Probe = [pscustomobject]@{
                LabRegistered = $false
                MissingVMs = @('dc1')
                LabReadyAvailable = $false
                SwitchPresent = $false
                NatPresent = $false
            }
            Failure = 'probe_timeout'
        }
        $result = Invoke-AppNoExecute -Action 'teardown' -Mode 'quick' -State @($hostProbeA, $hostProbeB) -TargetHosts @($targetHost)

        $result.PolicyOutcome | Should -Not -BeNullOrEmpty
        $result.PolicyReason | Should -Not -BeNullOrEmpty
        @($result.BlastRadius) | Should -Be @($targetHost)
        @($result.HostOutcomes).Count | Should -Be 2
        @($result.HostOutcomes | ForEach-Object { [string]$_.HostName }) | Should -Be @($targetHost, 'ignored-host')
    }

    It 'Write-RunArtifacts definitions include coordinator metadata keys for json and txt payloads' {
        $scriptContent = Get-Content -Path $appPath -Raw

        $scriptContent | Should -Match 'policy_outcome\s*='
        $scriptContent | Should -Match 'policy_reason\s*='
        $scriptContent | Should -Match 'host_outcomes\s*='
        $scriptContent | Should -Match 'blast_radius\s*='

        $scriptContent | Should -Match '"policy_outcome:\s*\$policyOutcome"'
        $scriptContent | Should -Match '"policy_reason:\s*\$policyReason"'
        $scriptContent | Should -Match '"host_outcomes:'
        $scriptContent | Should -Match '"blast_radius:\s*\$\(\$blastRadius\s*-join\s*'',''\)"'
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
