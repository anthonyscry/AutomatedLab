# Coordinator integration tests for OpenCodeLab-App routing

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $appPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'

    function Get-LatestRunReport {
        param(
            [Parameter(Mandatory)]
            [string]$LogRoot
        )

        $reportFile = Get-ChildItem -Path $LogRoot -Filter '*.json' |
            Sort-Object -Property LastWriteTimeUtc, Name -Descending |
            Select-Object -First 1
        $reportFile | Should -Not -BeNullOrEmpty
        return (Get-Content -Path $reportFile.FullName -Raw | ConvertFrom-Json)
    }
}

Describe 'OpenCodeLab-App coordinator pipeline integration' {
    BeforeEach {
        Remove-Item Env:OPENCODELAB_RUN_LOG_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_RUNTIME_STATE_JSON -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_DISABLE_COORDINATOR_DISPATCH -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_DISPATCH_FAILURE_HOSTS -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_DISPATCH_EXECUTION_MARKER -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_SIMULATE_LOCAL_DISPATCH_SUCCESS -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:OPENCODELAB_RUN_LOG_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_RUNTIME_STATE_JSON -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_DISABLE_COORDINATOR_DISPATCH -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_DISPATCH_FAILURE_HOSTS -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_DISPATCH_EXECUTION_MARKER -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS -ErrorAction SilentlyContinue
        Remove-Item Env:OPENCODELAB_TEST_SIMULATE_LOCAL_DISPATCH_SUCCESS -ErrorAction SilentlyContinue
    }

    It 'accepts inventory and target host inputs and returns approved policy in no-execute mode' {
        $inventoryPath = Join-Path $TestDrive 'inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "psremoting" },
    { "name": "hv-b", "role": "secondary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbe = [pscustomobject]@{
            HostName = 'hv-b'
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

        $result = & $appPath -Action deploy -Mode quick -NoExecute -InventoryPath $inventoryPath -TargetHosts @('hv-b') -NoExecuteStateJson (@($hostProbe) | ConvertTo-Json -Depth 10 -Compress)

        @($result.OperationIntent.TargetHosts) | Should -Be @('hv-b')
        $result.OperationIntent.InventorySource | Should -Be $inventoryPath
        $result.PolicyOutcome | Should -Be 'Approved'
        $result.PolicyReason | Should -Be 'approved'
        $result.DispatchMode | Should -Be 'off'
        $result.ExecutionOutcome | Should -Be 'not_dispatched'
        $result.ExecutionStartedAt | Should -Be $null
        $result.ExecutionCompletedAt | Should -Be $null
        @($result.HostOutcomes).Count | Should -Be 1
        @($result.HostOutcomes[0].PSObject.Properties.Name) | Should -Contain 'Reachable'
        @($result.HostOutcomes[0].PSObject.Properties.Name) | Should -Contain 'Probe'
        @($result.HostOutcomes[0].PSObject.Properties.Name) | Should -Not -Contain 'DispatchStatus'
    }

    It 'returns blocked policy fields when fleet probe is unreachable' {
        $inventoryPath = Join-Path $TestDrive 'unreachable-host-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-x", "role": "primary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbe = [pscustomobject]@{
            HostName = 'hv-x'
            Reachable = $false
            Probe = $null
            Failure = 'timeout'
        }

        $result = & $appPath -Action teardown -Mode full -NoExecute -InventoryPath $inventoryPath -TargetHosts @('hv-x') -NoExecuteStateJson (@($hostProbe) | ConvertTo-Json -Depth 10 -Compress)

        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.PolicyReason | Should -Be 'host_probe_unreachable:hv-x'
        $result.EffectiveMode | Should -Be 'full'
    }

    It 'returns deterministic blocked outcome when resolved target host set is empty' {
        $inventoryPath = Join-Path $TestDrive 'empty-targets-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $result = & $appPath -Action teardown -Mode full -NoExecute -InventoryPath $inventoryPath -TargetHosts @('hv-missing')

        @($result.OperationIntent.TargetHosts).Count | Should -Be 0
        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.PolicyReason | Should -Be 'target_hosts_empty'
        $result.EffectiveMode | Should -Be 'full'
        $result.DispatchMode | Should -Be 'off'
        $result.ExecutionOutcome | Should -Be 'not_dispatched'
        $result.ExecutionStartedAt | Should -Be $null
        $result.ExecutionCompletedAt | Should -Be $null
    }

    It 'non-noexecute canary dispatch writes dispatcher host outcomes and metadata artifacts' {
        $logRoot = Join-Path $TestDrive 'run-logs-canary'
        $env:OPENCODELAB_RUN_LOG_ROOT = $logRoot
        $env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP = '1'
        $env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS = '1'
        $markerPath = Join-Path $TestDrive 'dispatch-canary-marker.log'
        $env:OPENCODELAB_TEST_DISPATCH_EXECUTION_MARKER = $markerPath
        $inventoryPath = Join-Path $TestDrive 'runtime-canary-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "psremoting" },
    { "name": "hv-b", "role": "secondary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbes = @(
            [pscustomobject]@{
                HostName = 'hv-a'
                Reachable = $true
                Probe = [pscustomobject]@{
                    LabRegistered = $true
                    MissingVMs = @()
                    LabReadyAvailable = $true
                    SwitchPresent = $true
                    NatPresent = $true
                }
                Failure = $null
            },
            [pscustomobject]@{
                HostName = 'hv-b'
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
        )
        $env:OPENCODELAB_RUNTIME_STATE_JSON = ($hostProbes | ConvertTo-Json -Depth 10 -Compress)

        & $appPath -Action deploy -Mode quick -NonInteractive -DispatchMode canary -TargetHosts @('hv-a', 'hv-b') -InventoryPath $inventoryPath

        $report = Get-LatestRunReport -LogRoot $logRoot

        $report.dispatch_mode | Should -Be 'canary'
        $report.execution_outcome | Should -Be 'succeeded'
        @($report.host_outcomes).Count | Should -Be 2
        @($report.host_outcomes | ForEach-Object { [string]$_.DispatchStatus }) | Should -Be @('succeeded', 'not_dispatched')
        @($report.host_outcomes | ForEach-Object { [int]$_.AttemptCount }) | Should -Be @(1, 0)

        Test-Path $markerPath | Should -BeTrue
        @(Get-Content -Path $markerPath).Count | Should -Be 1
    }

    It 'non-noexecute enforced dispatch writes dispatcher outcomes for all targets' {
        $logRoot = Join-Path $TestDrive 'run-logs-enforced'
        $env:OPENCODELAB_RUN_LOG_ROOT = $logRoot
        $env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP = '1'
        $env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS = '1'
        $markerPath = Join-Path $TestDrive 'dispatch-enforced-marker.log'
        $env:OPENCODELAB_TEST_DISPATCH_EXECUTION_MARKER = $markerPath
        $inventoryPath = Join-Path $TestDrive 'runtime-enforced-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "psremoting" },
    { "name": "hv-b", "role": "secondary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbes = @(
            [pscustomobject]@{
                HostName = 'hv-a'
                Reachable = $true
                Probe = [pscustomobject]@{
                    LabRegistered = $true
                    MissingVMs = @()
                    LabReadyAvailable = $true
                    SwitchPresent = $true
                    NatPresent = $true
                }
                Failure = $null
            },
            [pscustomobject]@{
                HostName = 'hv-b'
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
        )
        $env:OPENCODELAB_RUNTIME_STATE_JSON = ($hostProbes | ConvertTo-Json -Depth 10 -Compress)

        & $appPath -Action deploy -Mode quick -NonInteractive -DispatchMode enforced -TargetHosts @('hv-a', 'hv-b') -InventoryPath $inventoryPath

        $report = Get-LatestRunReport -LogRoot $logRoot

        $report.dispatch_mode | Should -Be 'enforced'
        $report.execution_outcome | Should -Be 'succeeded'
        @($report.host_outcomes).Count | Should -Be 2
        @($report.host_outcomes | ForEach-Object { [string]$_.DispatchStatus }) | Should -Be @('succeeded', 'succeeded')
        @($report.host_outcomes | ForEach-Object { [int]$_.AttemptCount }) | Should -Be @(1, 1)

        Test-Path $markerPath | Should -BeTrue
        @(Get-Content -Path $markerPath).Count | Should -Be 2
    }

    It 'non-noexecute enforced dispatch partial outcome fails run and records failed artifact outcome' {
        $logRoot = Join-Path $TestDrive 'run-logs-enforced-partial'
        $env:OPENCODELAB_RUN_LOG_ROOT = $logRoot
        $env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP = '1'
        $env:OPENCODELAB_TEST_DISPATCH_FAILURE_HOSTS = 'hv-b'
        $env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS = '1'
        $markerPath = Join-Path $TestDrive 'dispatch-enforced-partial-marker.log'
        $env:OPENCODELAB_TEST_DISPATCH_EXECUTION_MARKER = $markerPath
        $inventoryPath = Join-Path $TestDrive 'runtime-enforced-partial-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "psremoting" },
    { "name": "hv-b", "role": "secondary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbes = @(
            [pscustomobject]@{
                HostName = 'hv-a'
                Reachable = $true
                Probe = [pscustomobject]@{
                    LabRegistered = $true
                    MissingVMs = @()
                    LabReadyAvailable = $true
                    SwitchPresent = $true
                    NatPresent = $true
                }
                Failure = $null
            },
            [pscustomobject]@{
                HostName = 'hv-b'
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
        )
        $env:OPENCODELAB_RUNTIME_STATE_JSON = ($hostProbes | ConvertTo-Json -Depth 10 -Compress)

        {
            & $appPath -Action deploy -Mode quick -NonInteractive -DispatchMode enforced -TargetHosts @('hv-a', 'hv-b') -InventoryPath $inventoryPath
        } | Should -Throw '*Coordinator dispatch did not succeed*hv-b*Host step runner returned unsuccessful result*'

        $report = Get-LatestRunReport -LogRoot $logRoot
        $report.dispatch_mode | Should -Be 'enforced'
        $report.success | Should -BeFalse
        $report.execution_outcome | Should -Be 'failed'
        @($report.host_outcomes).Count | Should -Be 2
        @($report.host_outcomes | ForEach-Object { [string]$_.DispatchStatus }) | Should -Be @('succeeded', 'failed')

        Test-Path $markerPath | Should -BeTrue
        @(Get-Content -Path $markerPath).Count | Should -Be 2
    }

    It 'canary dispatch mode fails fast when dispatcher is unavailable' {
        $logRoot = Join-Path $TestDrive 'run-logs-canary-no-dispatcher'
        $env:OPENCODELAB_RUN_LOG_ROOT = $logRoot
        $env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP = '1'
        $env:OPENCODELAB_TEST_DISABLE_COORDINATOR_DISPATCH = '1'
        $env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS = '1'
        $inventoryPath = Join-Path $TestDrive 'runtime-canary-no-dispatcher-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "psremoting" },
    { "name": "hv-b", "role": "secondary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbes = @(
            [pscustomobject]@{
                HostName = 'hv-a'
                Reachable = $true
                Probe = [pscustomobject]@{
                    LabRegistered = $true
                    MissingVMs = @()
                    LabReadyAvailable = $true
                    SwitchPresent = $true
                    NatPresent = $true
                }
                Failure = $null
            },
            [pscustomobject]@{
                HostName = 'hv-b'
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
        )
        $env:OPENCODELAB_RUNTIME_STATE_JSON = ($hostProbes | ConvertTo-Json -Depth 10 -Compress)

        { & $appPath -Action deploy -Mode quick -NonInteractive -DispatchMode canary -TargetHosts @('hv-a', 'hv-b') -InventoryPath $inventoryPath } | Should -Throw '*Dispatch mode canary requires Invoke-LabCoordinatorDispatch*'
    }

    It 'enforced dispatch mode fails fast when dispatcher is unavailable' {
        $logRoot = Join-Path $TestDrive 'run-logs-enforced-no-dispatcher'
        $env:OPENCODELAB_RUN_LOG_ROOT = $logRoot
        $env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP = '1'
        $env:OPENCODELAB_TEST_DISABLE_COORDINATOR_DISPATCH = '1'
        $env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS = '1'
        $inventoryPath = Join-Path $TestDrive 'runtime-enforced-no-dispatcher-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "psremoting" },
    { "name": "hv-b", "role": "secondary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbes = @(
            [pscustomobject]@{
                HostName = 'hv-a'
                Reachable = $true
                Probe = [pscustomobject]@{
                    LabRegistered = $true
                    MissingVMs = @()
                    LabReadyAvailable = $true
                    SwitchPresent = $true
                    NatPresent = $true
                }
                Failure = $null
            },
            [pscustomobject]@{
                HostName = 'hv-b'
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
        )
        $env:OPENCODELAB_RUNTIME_STATE_JSON = ($hostProbes | ConvertTo-Json -Depth 10 -Compress)

        { & $appPath -Action deploy -Mode quick -NonInteractive -DispatchMode enforced -TargetHosts @('hv-a', 'hv-b') -InventoryPath $inventoryPath } | Should -Throw '*Dispatch mode enforced requires Invoke-LabCoordinatorDispatch*'
    }

    It 'runtime state override env is ignored when bootstrap skip guard is disabled' {
        $env:OPENCODELAB_RUNTIME_STATE_JSON = '{"bad_json":'
        $result = & $appPath -Action deploy -Mode quick -NoExecute

        $result | Should -Not -BeNullOrEmpty
        $result.ExecutionOutcome | Should -Be 'not_dispatched'
    }

    It 'enforced dispatch fails closed for remote targets when simulated remote success hook is disabled' {
        $logRoot = Join-Path $TestDrive 'run-logs-enforced-remote-fail-closed'
        $env:OPENCODELAB_RUN_LOG_ROOT = $logRoot
        $env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP = '1'
        $inventoryPath = Join-Path $TestDrive 'runtime-enforced-remote-fail-closed-inventory.json'
        @'
{
  "hosts": [
    { "name": "hv-remote-a", "role": "primary", "connection": "psremoting" }
  ]
}
'@ | Set-Content -Path $inventoryPath -Encoding UTF8

        $hostProbes = @(
            [pscustomobject]@{
                HostName = 'hv-remote-a'
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
        )
        $env:OPENCODELAB_RUNTIME_STATE_JSON = ($hostProbes | ConvertTo-Json -Depth 10 -Compress)

        {
            & $appPath -Action deploy -Mode quick -NonInteractive -DispatchMode enforced -TargetHosts @('hv-remote-a') -InventoryPath $inventoryPath
        } | Should -Throw '*Remote dispatch target*requires an explicit remote execution implementation*'

        $report = Get-LatestRunReport -LogRoot $logRoot
        $report.execution_outcome | Should -Be 'failed'
    }
}
