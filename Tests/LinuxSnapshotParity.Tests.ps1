# LinuxSnapshotParity.Tests.ps1 -- Pester 5 tests for Linux VM snapshot parity
# Covers: Get-LabSnapshotInventory discovers all Linux VMs, Remove-LabStaleSnapshots
# processes Linux VM snapshots identically to Windows VMs.

BeforeAll {
    Set-StrictMode -Version Latest

    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $script:repoRoot 'Private' 'Get-LabSnapshotInventory.ps1')
    . (Join-Path $script:repoRoot 'Private' 'Remove-LabStaleSnapshots.ps1')

    # Stub Hyper-V cmdlets so tests run without Hyper-V module
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        function Get-VM { param([string]$Name, $ErrorAction) $null }
    }
    if (-not (Get-Command Get-VMCheckpoint -ErrorAction SilentlyContinue)) {
        function Get-VMCheckpoint { param([string]$VMName, $ErrorAction) @() }
    }
    if (-not (Get-Command Remove-VMCheckpoint -ErrorAction SilentlyContinue)) {
        function Remove-VMCheckpoint { param([string]$VMName, [string]$Name, $ErrorAction) }
    }
}

Describe 'Get-LabSnapshotInventory - Linux VM discovery with GlobalLabConfig' {
    BeforeEach {
        # Set up GlobalLabConfig with all 5 Linux VM name mappings
        $script:GlobalLabConfig = @{
            Lab = @{
                CoreVMNames = @('dc1', 'svr1', 'ws1')
            }
            Builder = @{
                VMNames = @{
                    Ubuntu         = 'LIN1'
                    WebServerUbuntu = 'LINWEB1'
                    DatabaseUbuntu  = 'LINDB1'
                    DockerUbuntu    = 'LINDOCK1'
                    K8sUbuntu       = 'LINK8S1'
                }
            }
        }
        Set-Variable -Name GlobalLabConfig -Value $script:GlobalLabConfig -Scope Global

        Mock Get-VM {
            param([string]$Name, $ErrorAction)
            [PSCustomObject]@{ Name = $Name; VMName = $Name; State = 'Running' }
        }
        Mock Get-VMCheckpoint {
            param([string]$VMName, $ErrorAction)
            @([PSCustomObject]@{
                VMName               = $VMName
                Name                 = 'LabReady'
                CreationTime         = (Get-Date).AddDays(-2)
                ParentCheckpointName = $null
            })
        }
    }

    AfterEach {
        Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
    }

    It 'discovers all 5 Linux VMs when GlobalLabConfig is loaded' {
        $results = Get-LabSnapshotInventory
        $vmNames = $results | Select-Object -ExpandProperty VMName -Unique
        $vmNames | Should -Contain 'LIN1'
        $vmNames | Should -Contain 'LINWEB1'
        $vmNames | Should -Contain 'LINDB1'
        $vmNames | Should -Contain 'LINDOCK1'
        $vmNames | Should -Contain 'LINK8S1'
    }

    It 'includes Linux VMs alongside Windows VMs in output' {
        $results = Get-LabSnapshotInventory
        $vmNames = $results | Select-Object -ExpandProperty VMName -Unique
        # Windows core VMs
        $vmNames | Should -Contain 'dc1'
        $vmNames | Should -Contain 'svr1'
        $vmNames | Should -Contain 'ws1'
        # Linux VMs
        $vmNames | Should -Contain 'LIN1'
        $vmNames | Should -Contain 'LINWEB1'
    }

    It 'returns snapshot objects with required properties for Linux VMs' {
        $results = Get-LabSnapshotInventory
        $linuxSnapshot = $results | Where-Object { $_.VMName -eq 'LIN1' } | Select-Object -First 1
        $linuxSnapshot | Should -Not -BeNullOrEmpty
        $linuxSnapshot.PSObject.Properties.Name | Should -Contain 'VMName'
        $linuxSnapshot.PSObject.Properties.Name | Should -Contain 'CheckpointName'
        $linuxSnapshot.PSObject.Properties.Name | Should -Contain 'CreationTime'
        $linuxSnapshot.PSObject.Properties.Name | Should -Contain 'AgeDays'
        $linuxSnapshot.PSObject.Properties.Name | Should -Contain 'ParentCheckpointName'
    }

    It 'skips Linux VM if Get-VM returns null for it' {
        Mock Get-VM {
            param([string]$Name, $ErrorAction)
            # Simulate only LIN1 and Windows VMs exist; others not found
            if ($Name -in @('dc1', 'svr1', 'ws1', 'LIN1')) {
                [PSCustomObject]@{ Name = $Name; VMName = $Name; State = 'Running' }
            }
            else {
                $null
            }
        }
        $results = Get-LabSnapshotInventory
        $vmNames = $results | Select-Object -ExpandProperty VMName -Unique
        $vmNames | Should -Contain 'LIN1'
        $vmNames | Should -Not -Contain 'LINWEB1'
        $vmNames | Should -Not -Contain 'LINDB1'
    }

    It 'respects explicit VMName parameter - does not auto-add Linux VMs' {
        $results = Get-LabSnapshotInventory -VMName 'dc1'
        $vmNames = $results | Select-Object -ExpandProperty VMName -Unique
        $vmNames | Should -Contain 'dc1'
        $vmNames | Should -Not -Contain 'LIN1'
        $vmNames | Should -Not -Contain 'LINWEB1'
    }
}

Describe 'Get-LabSnapshotInventory - Backward compat when GlobalLabConfig not loaded' {
    BeforeEach {
        # Ensure GlobalLabConfig is NOT in scope
        Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue

        Mock Get-VM {
            param([string]$Name, $ErrorAction)
            if ($Name -eq 'LIN1') {
                [PSCustomObject]@{ Name = 'LIN1'; VMName = 'LIN1'; State = 'Running' }
            }
            else {
                [PSCustomObject]@{ Name = $Name; VMName = $Name; State = 'Running' }
            }
        }
        Mock Get-VMCheckpoint {
            param([string]$VMName, $ErrorAction)
            @([PSCustomObject]@{
                VMName               = $VMName
                Name                 = 'LabReady'
                CreationTime         = (Get-Date).AddDays(-1)
                ParentCheckpointName = $null
            })
        }
    }

    It 'auto-detects LIN1 via fallback when GlobalLabConfig is absent' {
        $results = Get-LabSnapshotInventory
        $vmNames = $results | Select-Object -ExpandProperty VMName -Unique
        $vmNames | Should -Contain 'LIN1'
    }

    It 'uses default CoreVMNames fallback (dc1, svr1, ws1) when GlobalLabConfig absent' {
        $results = Get-LabSnapshotInventory
        $vmNames = $results | Select-Object -ExpandProperty VMName -Unique
        $vmNames | Should -Contain 'dc1'
        $vmNames | Should -Contain 'svr1'
        $vmNames | Should -Contain 'ws1'
    }

    It 'does not add LIN1 twice if LIN1 already in target list' {
        # If someone passes -VMName @('LIN1') explicitly, LIN1 should not be duplicated
        $results = Get-LabSnapshotInventory -VMName 'LIN1'
        $lin1Results = @($results | Where-Object { $_.VMName -eq 'LIN1' })
        # With explicit VMName, no auto-detection runs -- just that one VM
        $lin1Results | Should -Not -BeNullOrEmpty
        $vmNames = @($results | Select-Object -ExpandProperty VMName -Unique)
        @($vmNames | Where-Object { $_ -eq 'LIN1' }).Count | Should -Be 1
    }
}

Describe 'Remove-LabStaleSnapshots - Linux VM snapshot pruning parity' {
    BeforeEach {
        $script:GlobalLabConfig = @{
            Lab = @{
                CoreVMNames = @('dc1', 'svr1')
            }
            Builder = @{
                VMNames = @{
                    Ubuntu         = 'LIN1'
                    WebServerUbuntu = 'LINWEB1'
                    DatabaseUbuntu  = 'LINDB1'
                    DockerUbuntu    = 'LINDOCK1'
                    K8sUbuntu       = 'LINK8S1'
                }
            }
        }
        Set-Variable -Name GlobalLabConfig -Value $script:GlobalLabConfig -Scope Global

        Mock Get-VM {
            param([string]$Name, $ErrorAction)
            [PSCustomObject]@{ Name = $Name; VMName = $Name; State = 'Running' }
        }
        Mock Get-VMCheckpoint {
            param([string]$VMName, $ErrorAction)
            # Return a stale checkpoint (10 days old) for all VMs
            @([PSCustomObject]@{
                VMName               = $VMName
                Name                 = 'OldSnapshot'
                CreationTime         = (Get-Date).AddDays(-10)
                ParentCheckpointName = $null
            })
        }
        Mock Remove-VMCheckpoint { }
    }

    AfterEach {
        Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
    }

    It 'calls Remove-VMCheckpoint for stale Linux VM snapshots' {
        $result = Remove-LabStaleSnapshots -OlderThanDays 7 -Confirm:$false
        Should -Invoke Remove-VMCheckpoint -Times 1 -Scope It -ParameterFilter { $VMName -eq 'LIN1' }
    }

    It 'processes Linux VM snapshots identically to Windows VM snapshots' {
        $result = Remove-LabStaleSnapshots -OlderThanDays 7 -Confirm:$false
        $result.OverallStatus | Should -Be 'OK'
        $removedVMs = $result.Removed | Select-Object -ExpandProperty VMName
        $removedVMs | Should -Contain 'dc1'
        $removedVMs | Should -Contain 'LIN1'
        $removedVMs | Should -Contain 'LINWEB1'
        $removedVMs | Should -Contain 'LINDB1'
        $removedVMs | Should -Contain 'LINDOCK1'
        $removedVMs | Should -Contain 'LINK8S1'
    }

    It 'returns NoStale when no Linux VM snapshots exceed threshold' {
        Mock Get-VMCheckpoint {
            param([string]$VMName, $ErrorAction)
            # Fresh checkpoint (1 day old)
            @([PSCustomObject]@{
                VMName               = $VMName
                Name                 = 'FreshSnapshot'
                CreationTime         = (Get-Date).AddDays(-1)
                ParentCheckpointName = $null
            })
        }
        $result = Remove-LabStaleSnapshots -OlderThanDays 7 -Confirm:$false
        $result.OverallStatus | Should -Be 'NoStale'
        $result.TotalFound | Should -Be 0
    }

    It 'supports WhatIf for Linux VM snapshot removal' {
        $result = Remove-LabStaleSnapshots -OlderThanDays 7 -WhatIf
        # With WhatIf, no actual Remove-VMCheckpoint should fire
        Should -Invoke Remove-VMCheckpoint -Times 0 -Scope It
    }
}
