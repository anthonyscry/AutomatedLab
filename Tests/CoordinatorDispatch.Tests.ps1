# Invoke-LabCoordinatorDispatch tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Test-LabTransientTransportFailure.ps1')

    $targetFile = Join-Path $repoRoot 'Private/Invoke-LabCoordinatorDispatch.ps1'
    if (Test-Path $targetFile) {
        . $targetFile
    }
}

Describe 'Invoke-LabCoordinatorDispatch' {
    It 'returns not_dispatched when dispatch mode is off' {
        $script:runnerCalls = 0

        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'quick' -DispatchMode 'off' -TargetHosts @('host-a', 'host-b') -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            $script:runnerCalls++
            return $true
        }

        $script:runnerCalls | Should -Be 0
        $result.ExecutionOutcome | Should -Be 'not_dispatched'
        @($result.HostOutcomes).Count | Should -Be 2
        @($result.HostOutcomes | Where-Object { $_.DispatchStatus -eq 'not_dispatched' }).Count | Should -Be 2
    }

    It 'dispatches only one host in canary mode' {
        $script:runnerCalls = 0

        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'quick' -DispatchMode 'canary' -TargetHosts @('host-a', 'host-b', 'host-c') -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            $script:runnerCalls++
            return $true
        }

        $script:runnerCalls | Should -Be 1
        @($result.HostOutcomes).Count | Should -Be 3
        @($result.HostOutcomes | Where-Object { $_.DispatchStatus -eq 'succeeded' }).Count | Should -Be 1
        @($result.HostOutcomes | Where-Object { $_.DispatchStatus -eq 'not_dispatched' }).Count | Should -Be 2
    }

    It 'fails fast for full teardown and skips remaining hosts after first failure' {
        $script:runnerCalls = 0

        $result = Invoke-LabCoordinatorDispatch -Action 'teardown' -EffectiveMode 'full' -DispatchMode 'enforced' -TargetHosts @('host-a', 'host-b', 'host-c') -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            $script:runnerCalls++
            throw 'Teardown failed hard.'
        }

        $script:runnerCalls | Should -Be 1
        $result.ExecutionOutcome | Should -Be 'failed'

        $firstHost = $result.HostOutcomes[0]
        $firstHost.HostName | Should -Be 'host-a'
        $firstHost.DispatchStatus | Should -Be 'failed'
        $firstHost.AttemptCount | Should -Be 1
        $firstHost.LastFailureClass | Should -Be 'non_transient'
        $firstHost.LastFailureMessage | Should -Be 'Teardown failed hard.'

        @($result.HostOutcomes | Where-Object { $_.DispatchStatus -eq 'skipped' }).Count | Should -Be 2
    }

    It 'continues deploy after one host failure and reports partial outcome' {
        $script:runnerCalls = 0

        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'full' -DispatchMode 'enforced' -TargetHosts @('host-a', 'host-b', 'host-c') -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            $script:runnerCalls++
            if ($HostName -eq 'host-b') {
                throw 'Non-transient deployment failure.'
            }

            return $true
        }

        $script:runnerCalls | Should -Be 3
        $result.ExecutionOutcome | Should -Be 'partial'
        @($result.HostOutcomes | Where-Object { $_.DispatchStatus -eq 'failed' }).Count | Should -Be 1
        @($result.HostOutcomes | Where-Object { $_.DispatchStatus -eq 'succeeded' }).Count | Should -Be 2
    }

    It 'retries transient failures up to max retry count and can succeed' {
        $script:attemptByHost = @{}

        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'full' -DispatchMode 'enforced' -TargetHosts @('host-a') -MaxRetryCount 2 -RetryDelayMilliseconds 0 -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)

            if (-not $script:attemptByHost.ContainsKey($HostName)) {
                $script:attemptByHost[$HostName] = 0
            }

            $script:attemptByHost[$HostName]++

            if ($script:attemptByHost[$HostName] -lt 3) {
                throw 'WinRM operation timed out while waiting for a response.'
            }

            return $true
        }

        $hostOutcome = $result.HostOutcomes[0]
        $hostOutcome.DispatchStatus | Should -Be 'succeeded'
        $hostOutcome.AttemptCount | Should -Be 3
        $hostOutcome.LastFailureClass | Should -BeNullOrEmpty
        $hostOutcome.LastFailureMessage | Should -BeNullOrEmpty
        $result.ExecutionOutcome | Should -Be 'succeeded'
    }

    It 'throws when target hosts array is empty' {
        {
            Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'quick' -DispatchMode 'enforced' -TargetHosts @()
        } | Should -Throw
    }

    It 'throws when target hosts contain only whitespace' {
        {
            Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'quick' -DispatchMode 'enforced' -TargetHosts @('', '  ')
        } | Should -Throw
    }

    It 'handles runner returning string truthy value' {
        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'quick' -DispatchMode 'enforced' -TargetHosts @('host-a') -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            return 'completed'
        }

        $result.HostOutcomes[0].DispatchStatus | Should -Be 'succeeded'
    }

    It 'exhausts retries on persistent transient failure and reports failed with attempt count' {
        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'quick' -DispatchMode 'enforced' -TargetHosts @('host-a') -MaxRetryCount 2 -RetryDelayMilliseconds 0 -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            throw 'ssh: connect to host 10.0.0.5 port 22: Connection refused'
        }

        $hostOutcome = $result.HostOutcomes[0]
        $hostOutcome.DispatchStatus | Should -Be 'failed'
        $hostOutcome.AttemptCount | Should -Be 3
        $hostOutcome.LastFailureClass | Should -Be 'transient'
        $hostOutcome.LastFailureMessage | Should -BeLike '*Connection refused*'
        $result.ExecutionOutcome | Should -Be 'failed'
    }

    It 'does not retry non-transient auth failure and reports single attempt' {
        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'quick' -DispatchMode 'enforced' -TargetHosts @('host-a') -MaxRetryCount 2 -RetryDelayMilliseconds 0 -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            throw 'Access is denied.'
        }

        $hostOutcome = $result.HostOutcomes[0]
        $hostOutcome.DispatchStatus | Should -Be 'failed'
        $hostOutcome.AttemptCount | Should -Be 1
        $hostOutcome.LastFailureClass | Should -Be 'non_transient'
        $hostOutcome.LastFailureMessage | Should -Be 'Access is denied.'
    }

    It 'includes host name in every outcome even when all hosts fail' {
        $result = Invoke-LabCoordinatorDispatch -Action 'deploy' -EffectiveMode 'full' -DispatchMode 'enforced' -TargetHosts @('host-a', 'host-b') -HostStepRunner {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            throw "Failed on $HostName"
        }

        @($result.HostOutcomes).Count | Should -Be 2
        $result.HostOutcomes[0].HostName | Should -Be 'host-a'
        $result.HostOutcomes[0].LastFailureMessage | Should -Be 'Failed on host-a'
        $result.HostOutcomes[1].HostName | Should -Be 'host-b'
        $result.HostOutcomes[1].LastFailureMessage | Should -Be 'Failed on host-b'
        $result.ExecutionOutcome | Should -Be 'failed'
    }
}
