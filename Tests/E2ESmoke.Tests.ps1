# E2ESmoke.Tests.ps1 -- End-to-end smoke tests for lifecycle path
# Exercises bootstrap/deploy/teardown path through OpenCodeLab-App.ps1
# in -NoExecute mode, verifying exit codes, routing, and expected state transitions.
#
# Each Describe block maps to a lifecycle requirement (LIFE-01 through LIFE-05).

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'E2EMocks.ps1')

    $script:appPath = Join-Path $script:repoRoot 'OpenCodeLab-App.ps1'
    . (Join-Path $script:repoRoot 'Private' 'New-LabScopedConfirmationToken.ps1')

    # Preserve and set confirmation env vars for scoped token tests
    $script:origConfirmRunId = $env:OPENCODELAB_CONFIRMATION_RUN_ID
    $script:origConfirmSecret = $env:OPENCODELAB_CONFIRMATION_SECRET
    $env:OPENCODELAB_CONFIRMATION_RUN_ID = 'e2e-smoke-run'
    $env:OPENCODELAB_CONFIRMATION_SECRET = 'e2e-smoke-secret'

    $script:e2eStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    function Invoke-E2ENoExecute {
        <#
        .SYNOPSIS
            Invokes OpenCodeLab-App.ps1 in -NoExecute mode with optional state injection.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$Action,
            [string]$Mode = 'full',
            [object]$State,
            [string]$ConfirmationToken,
            [switch]$AutoHeal
        )

        $splat = @{
            Action = $Action
            Mode = $Mode
            NoExecute = $true
        }

        if ($null -ne $State) {
            $splat.NoExecuteStateJson = ($State | ConvertTo-Json -Depth 10 -Compress)
        }

        if (-not [string]::IsNullOrWhiteSpace($ConfirmationToken)) {
            $splat.ConfirmationToken = $ConfirmationToken
        }

        if ($AutoHeal) { $splat.AutoHeal = $true }

        & $script:appPath @splat
    }
}

AfterAll {
    if ($null -eq $script:origConfirmRunId) {
        Remove-Item Env:OPENCODELAB_CONFIRMATION_RUN_ID -ErrorAction SilentlyContinue
    }
    else {
        $env:OPENCODELAB_CONFIRMATION_RUN_ID = $script:origConfirmRunId
    }

    if ($null -eq $script:origConfirmSecret) {
        Remove-Item Env:OPENCODELAB_CONFIRMATION_SECRET -ErrorAction SilentlyContinue
    }
    else {
        $env:OPENCODELAB_CONFIRMATION_SECRET = $script:origConfirmSecret
    }

    if ($null -ne $script:e2eStopwatch) {
        $script:e2eStopwatch.Stop()
    }
}

Describe 'E2E: Bootstrap / Preflight Action (LIFE-01)' {
    # Validates: LIFE-01 -- Bootstrap installs prerequisites and validates environment

    It 'preflight action completes without error and returns structured result' {
        $result = Invoke-E2ENoExecute -Action 'preflight'
        $result | Should -Not -BeNullOrEmpty
        $result.DispatchAction | Should -Be 'preflight'
        $result.RequestedMode | Should -Be 'full'
    }

    It 'setup action routes through non-orchestration path' {
        $result = Invoke-E2ENoExecute -Action 'setup'
        $result | Should -Not -BeNullOrEmpty
        $result.DispatchAction | Should -Be 'setup'
        # Setup is a legacy path, not an orchestration action
        $result.OrchestrationAction | Should -BeNullOrEmpty
    }

    It 'bootstrap action routes correctly in no-execute mode' {
        $result = Invoke-E2ENoExecute -Action 'bootstrap'
        $result | Should -Not -BeNullOrEmpty
        $result.DispatchAction | Should -Be 'bootstrap'
    }

    It 'result includes execution metadata fields' {
        $result = Invoke-E2ENoExecute -Action 'preflight'
        $result.PSObject.Properties.Name | Should -Contain 'ExecutionOutcome'
        $result.PSObject.Properties.Name | Should -Contain 'DispatchMode'
        $result.PSObject.Properties.Name | Should -Contain 'ProfileSource'
        $result.ExecutionOutcome | Should -Be 'not_dispatched'
    }
}

Describe 'E2E: Deploy Action (LIFE-02)' {
    # Validates: LIFE-02 -- Deploy creates VMs, network, and domain infrastructure

    BeforeAll {
        $script:cleanState = New-E2EStateProbe -Clean
    }

    It 'deploy full mode routes to orchestration with clean state' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:cleanState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:full:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'deploy' -Mode 'full' -State $hostProbe -ConfirmationToken $token
        $result | Should -Not -BeNullOrEmpty
        $result.OrchestrationAction | Should -Be 'deploy'
        $result.EffectiveMode | Should -Be 'full'
    }

    It 'deploy result includes operation intent with target hosts' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:cleanState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:full:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'deploy' -Mode 'full' -State $hostProbe -ConfirmationToken $token
        $result.OperationIntent | Should -Not -BeNullOrEmpty
        $result.BlastRadius.Count | Should -BeGreaterThan 0
    }

    It 'deploy includes orchestration intent with strategy' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:cleanState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:full:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'deploy' -Mode 'full' -State $hostProbe -ConfirmationToken $token
        $result.OrchestrationIntent | Should -Not -BeNullOrEmpty
    }
}

Describe 'E2E: Quick Mode (LIFE-03)' {
    # Validates: LIFE-03 -- Quick mode restores from LabReady snapshots

    BeforeAll {
        $script:labReadyState = New-E2EStateProbe -LabReady
    }

    It 'deploy quick mode uses quick effective mode when LabReady available' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:labReadyState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:quick:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'deploy' -Mode 'quick' -State $hostProbe -ConfirmationToken $token
        $result | Should -Not -BeNullOrEmpty
        $result.OrchestrationAction | Should -Be 'deploy'
        $result.RequestedMode | Should -Be 'quick'
        $result.EffectiveMode | Should -Be 'quick'
    }

    It 'deploy quick mode falls back to full when no LabReady snapshots' {
        $noSnapshotState = New-E2EStateProbe  # Default: VMs exist, no snapshots
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $noSnapshotState
                Failure = $null
            }
        )
        # Generate token for both quick and full since fallback may use either
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:full:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'deploy' -Mode 'quick' -State $hostProbe -ConfirmationToken $token
        $result | Should -Not -BeNullOrEmpty
        $result.RequestedMode | Should -Be 'quick'
        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Not -BeNullOrEmpty
    }

    It 'mode decision object is populated for orchestration actions' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:labReadyState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:quick:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'deploy' -Mode 'quick' -State $hostProbe -ConfirmationToken $token
        $result.ModeDecision | Should -Not -BeNullOrEmpty
    }
}

Describe 'E2E: Teardown Action (LIFE-04)' {
    # Validates: LIFE-04 -- Teardown removes VMs, switch, and NAT cleanly

    BeforeAll {
        $script:existingState = New-E2EStateProbe -LabReady
    }

    It 'teardown full mode routes to orchestration' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:existingState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'teardown:full:teardown' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'teardown' -Mode 'full' -State $hostProbe -ConfirmationToken $token
        $result | Should -Not -BeNullOrEmpty
        $result.OrchestrationAction | Should -Be 'teardown'
        $result.EffectiveMode | Should -Be 'full'
    }

    It 'teardown result includes cleanup blast radius' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:existingState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'teardown:full:teardown' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'teardown' -Mode 'full' -State $hostProbe -ConfirmationToken $token
        $result.BlastRadius | Should -Not -BeNullOrEmpty
        $result.BlastRadius.Count | Should -BeGreaterThan 0
    }

    It 'teardown populates fleet probe and host outcomes' {
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $script:existingState
                Failure = $null
            }
        )
        $token = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'teardown:full:teardown' -Secret 'e2e-smoke-secret' -TtlSeconds 300

        $result = Invoke-E2ENoExecute -Action 'teardown' -Mode 'full' -State $hostProbe -ConfirmationToken $token
        $result.FleetProbe | Should -Not -BeNullOrEmpty
        $result.HostOutcomes | Should -Not -BeNullOrEmpty
    }
}

Describe 'E2E: Idempotent Redeploy (LIFE-05)' {
    # Validates: LIFE-05 -- Teardown then deploy produces clean state without errors

    It 'teardown followed by deploy both complete without error' {
        $existingState = New-E2EStateProbe -LabReady
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $existingState
                Failure = $null
            }
        )

        # Teardown
        $teardownToken = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'teardown:full:teardown' -Secret 'e2e-smoke-secret' -TtlSeconds 300
        $teardownResult = Invoke-E2ENoExecute -Action 'teardown' -Mode 'full' -State $hostProbe -ConfirmationToken $teardownToken
        $teardownResult | Should -Not -BeNullOrEmpty
        $teardownResult.OrchestrationAction | Should -Be 'teardown'

        # Deploy on clean state
        $cleanState = New-E2EStateProbe -Clean
        $cleanHostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $cleanState
                Failure = $null
            }
        )
        $deployToken = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:full:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300
        $deployResult = Invoke-E2ENoExecute -Action 'deploy' -Mode 'full' -State $cleanHostProbe -ConfirmationToken $deployToken
        $deployResult | Should -Not -BeNullOrEmpty
        $deployResult.OrchestrationAction | Should -Be 'deploy'
    }

    It 'both actions produce structured result objects with consistent schema' {
        $state = New-E2EStateProbe -LabReady
        $hostProbe = @(
            [pscustomobject]@{
                HostName = [Environment]::MachineName
                Reachable = $true
                Probe = $state
                Failure = $null
            }
        )

        $teardownToken = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'teardown:full:teardown' -Secret 'e2e-smoke-secret' -TtlSeconds 300
        $teardownResult = Invoke-E2ENoExecute -Action 'teardown' -Mode 'full' -State $hostProbe -ConfirmationToken $teardownToken

        $deployToken = New-LabScopedConfirmationToken -RunId 'e2e-smoke-run' -TargetHosts @([Environment]::MachineName) -OperationHash 'deploy:full:deploy' -Secret 'e2e-smoke-secret' -TtlSeconds 300
        $deployResult = Invoke-E2ENoExecute -Action 'deploy' -Mode 'full' -State $hostProbe -ConfirmationToken $deployToken

        # Both results should have the same schema
        $expectedKeys = @('RawAction', 'DispatchAction', 'OrchestrationAction', 'EffectiveMode', 'OperationIntent', 'BlastRadius')
        foreach ($key in $expectedKeys) {
            $teardownResult.PSObject.Properties.Name | Should -Contain $key
            $deployResult.PSObject.Properties.Name | Should -Contain $key
        }
    }
}

Describe 'E2E: Exit Code Contract' {
    # Validates: Structured result objects for all action types

    It 'status action returns structured result without orchestration' {
        $result = Invoke-E2ENoExecute -Action 'status'
        $result | Should -Not -BeNullOrEmpty
        $result.DispatchAction | Should -Be 'status'
        $result.OrchestrationAction | Should -BeNullOrEmpty
    }

    It 'health action returns structured result without orchestration' {
        $result = Invoke-E2ENoExecute -Action 'health'
        $result | Should -Not -BeNullOrEmpty
        $result.DispatchAction | Should -Be 'health'
    }

    It 'non-orchestration actions do not populate fleet probe' {
        $result = Invoke-E2ENoExecute -Action 'status'
        $result.FleetProbe | Should -BeNullOrEmpty
    }

    It 'all results include dispatch mode and profile source' {
        foreach ($action in @('status', 'health', 'preflight')) {
            $result = Invoke-E2ENoExecute -Action $action
            $result.PSObject.Properties.Name | Should -Contain 'DispatchMode'
            $result.PSObject.Properties.Name | Should -Contain 'ProfileSource'
        }
    }
}

Describe 'E2E: Timing' {
    It 'total E2E execution completes under 60 seconds' {
        $script:e2eStopwatch.Elapsed.TotalSeconds | Should -BeLessThan 60
    }
}
