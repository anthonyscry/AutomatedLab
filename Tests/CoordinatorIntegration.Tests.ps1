# Coordinator integration tests for OpenCodeLab-App routing

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $appPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'
}

Describe 'OpenCodeLab-App coordinator pipeline integration' {
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
}
