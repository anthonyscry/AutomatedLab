BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    # Stub Hyper-V cmdlets on non-Windows / no Hyper-V so Pester can mock them
    if (-not (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
        function global:Get-VM { param([string]$Name, [string]$VMName) throw 'Get-VM is not available on this platform' }
    }
    if (-not (Get-Command -Name Get-VMCheckpoint -ErrorAction SilentlyContinue)) {
        function global:Get-VMCheckpoint { param([string]$VMName) throw 'Get-VMCheckpoint is not available on this platform' }
    }
    if (-not (Get-Command -Name Remove-VMCheckpoint -ErrorAction SilentlyContinue)) {
        function global:Remove-VMCheckpoint { param([string]$VMName, [string]$Name) throw 'Remove-VMCheckpoint is not available on this platform' }
    }
    . (Join-Path $script:repoRoot 'Private' 'Get-LabSnapshotInventory.ps1')
    . (Join-Path $script:repoRoot 'Private' 'Remove-LabStaleSnapshots.ps1')
}

Describe 'Get-LabSnapshotInventory' {
    BeforeEach {
        $Global:GlobalLabConfig = @{ Lab = @{ CoreVMNames = @('dc1', 'svr1', 'ws1') } }

        $script:now = Get-Date
        $script:threeDaysAgo = $script:now.AddDays(-3)
        $script:tenDaysAgo = $script:now.AddDays(-10)

        $script:mockCheckpoints = @(
            [PSCustomObject]@{
                Name                 = 'LabReady'
                CreationTime         = $script:tenDaysAgo
                ParentCheckpointName = $null
            },
            [PSCustomObject]@{
                Name                 = 'AfterConfig'
                CreationTime         = $script:threeDaysAgo
                ParentCheckpointName = 'LabReady'
            }
        )

        Mock Get-VM { [PSCustomObject]@{ Name = $VMName } } -ParameterFilter { $VMName -ne 'LIN1' }
        Mock Get-VM { $null } -ParameterFilter { $VMName -eq 'LIN1' }
        Mock Get-VMCheckpoint { $script:mockCheckpoints }
    }

    AfterEach {
        Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Returns snapshot objects with correct properties' {
        $result = Get-LabSnapshotInventory
        $result | Should -Not -BeNullOrEmpty
        $first = $result[0]
        $first.PSObject.Properties.Name | Should -Contain 'VMName'
        $first.PSObject.Properties.Name | Should -Contain 'CheckpointName'
        $first.PSObject.Properties.Name | Should -Contain 'CreationTime'
        $first.PSObject.Properties.Name | Should -Contain 'AgeDays'
        $first.PSObject.Properties.Name | Should -Contain 'ParentCheckpointName'
    }

    It 'Calculates AgeDays correctly' {
        $result = Get-LabSnapshotInventory
        # Find the 3-day-old checkpoint
        $recent = $result | Where-Object { $_.CheckpointName -eq 'AfterConfig' } | Select-Object -First 1
        $recent.AgeDays | Should -BeGreaterOrEqual 2.9
        $recent.AgeDays | Should -BeLessOrEqual 3.2
    }

    It 'Sets ParentCheckpointName to (root) when parent is null' {
        $result = Get-LabSnapshotInventory
        $root = $result | Where-Object { $_.CheckpointName -eq 'LabReady' } | Select-Object -First 1
        $root.ParentCheckpointName | Should -Be '(root)'
    }

    It 'Returns ParentCheckpointName when parent exists' {
        $result = Get-LabSnapshotInventory
        $child = $result | Where-Object { $_.CheckpointName -eq 'AfterConfig' } | Select-Object -First 1
        $child.ParentCheckpointName | Should -Be 'LabReady'
    }

    It 'Returns empty array when no VMs have checkpoints' {
        Mock Get-VMCheckpoint { @() }
        $result = Get-LabSnapshotInventory
        $result | Should -HaveCount 0
    }

    It 'Skips non-existent VMs without error' {
        Mock Get-VM { $null } -ParameterFilter { $VMName -ne 'LIN1' }
        Mock Get-VM { $null } -ParameterFilter { $VMName -eq 'LIN1' }
        Mock Get-VMCheckpoint { @() }
        { $result = Get-LabSnapshotInventory } | Should -Not -Throw
        $result = Get-LabSnapshotInventory
        $result | Should -HaveCount 0
    }

    It 'Includes LIN1 when Get-VM finds it' {
        Mock Get-VM { [PSCustomObject]@{ Name = $VMName } }
        Mock Get-VMCheckpoint {
            @([PSCustomObject]@{
                Name                 = 'LinSnap'
                CreationTime         = $script:threeDaysAgo
                ParentCheckpointName = $null
            })
        }
        $result = Get-LabSnapshotInventory
        $lin1Snaps = $result | Where-Object { $_.VMName -eq 'LIN1' }
        $lin1Snaps | Should -Not -BeNullOrEmpty
    }

    It 'Results sorted by CreationTime ascending' {
        $result = Get-LabSnapshotInventory
        for ($i = 1; $i -lt $result.Count; $i++) {
            $result[$i].CreationTime | Should -BeGreaterOrEqual $result[$i - 1].CreationTime
        }
    }

    It 'Filters by -VMName parameter when provided' {
        $result = Get-LabSnapshotInventory -VMName 'dc1'
        $vmNames = $result | ForEach-Object { $_.VMName } | Sort-Object -Unique
        $vmNames | Should -Contain 'dc1'
        $vmNames | Should -Not -Contain 'svr1'
    }
}

Describe 'Remove-LabStaleSnapshots' {
    BeforeEach {
        $Global:GlobalLabConfig = @{ Lab = @{ CoreVMNames = @('dc1', 'svr1', 'ws1') } }

        $script:now = Get-Date
        $script:oldSnap = [PSCustomObject]@{
            VMName               = 'dc1'
            CheckpointName       = 'OldSnap'
            CreationTime         = $script:now.AddDays(-10)
            AgeDays              = 10.0
            ParentCheckpointName = '(root)'
        }
        $script:recentSnap = [PSCustomObject]@{
            VMName               = 'svr1'
            CheckpointName       = 'RecentSnap'
            CreationTime         = $script:now.AddDays(-2)
            AgeDays              = 2.0
            ParentCheckpointName = '(root)'
        }

        Mock Get-LabSnapshotInventory { @($script:oldSnap, $script:recentSnap) }
        Mock Remove-VMCheckpoint { }
    }

    AfterEach {
        Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Removes only snapshots older than threshold (default 7 days)' {
        $result = Remove-LabStaleSnapshots
        $result.TotalFound | Should -Be 1
        $result.TotalRemoved | Should -Be 1
        $result.Removed[0].CheckpointName | Should -Be 'OldSnap'
        Should -Invoke Remove-VMCheckpoint -Times 1 -Exactly
    }

    It 'Returns NoStale status when no snapshots exceed threshold' {
        Mock Get-LabSnapshotInventory { @($script:recentSnap) }
        $result = Remove-LabStaleSnapshots
        $result.OverallStatus | Should -Be 'NoStale'
        $result.TotalFound | Should -Be 0
        Should -Invoke Remove-VMCheckpoint -Times 0 -Exactly
    }

    It 'Custom threshold via -OlderThanDays parameter works' {
        $result = Remove-LabStaleSnapshots -OlderThanDays 1
        $result.TotalFound | Should -Be 2
        $result.TotalRemoved | Should -Be 2
        Should -Invoke Remove-VMCheckpoint -Times 2 -Exactly
    }

    It 'Returns correct TotalFound and TotalRemoved counts' {
        $result = Remove-LabStaleSnapshots
        $result.TotalFound | Should -Be 1
        $result.TotalRemoved | Should -Be 1
    }

    It 'Handles removal failure gracefully' {
        Mock Remove-VMCheckpoint { throw 'Access denied' }
        $result = Remove-LabStaleSnapshots
        $result.OverallStatus | Should -Be 'Partial'
        $result.Failed | Should -HaveCount 1
        $result.Failed[0].ErrorMessage | Should -BeLike '*Access denied*'
        $result.TotalRemoved | Should -Be 0
    }

    It 'Result contains ThresholdDays matching input parameter' {
        $result = Remove-LabStaleSnapshots -OlderThanDays 14
        $result.ThresholdDays | Should -Be 14
    }

    It 'ShouldProcess is respected with -WhatIf' {
        $result = Remove-LabStaleSnapshots -WhatIf
        Should -Invoke Remove-VMCheckpoint -Times 0 -Exactly
    }

    It 'Passes -VMName through to Get-LabSnapshotInventory' {
        Remove-LabStaleSnapshots -VMName 'dc1'
        Should -Invoke Get-LabSnapshotInventory -Times 1 -Exactly -ParameterFilter {
            $VMName -contains 'dc1'
        }
    }
}

AfterAll {
    Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
}
