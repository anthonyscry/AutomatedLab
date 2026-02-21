BeforeAll {
    # Stub missing Hyper-V cmdlets as global functions (Phase 27-03 pattern)
    function global:Get-VMSnapshot { }
    function global:Get-VMHardDiskDrive { }
    function global:Get-VHD { }

    # Mock helper functions from other phases BEFORE dot-sourcing
    function Get-LabUptime {
        return [pscustomobject]@{ ElapsedHours = 5.5 }
    }
    function Get-LabSTIGCompliance {
        return @(
            [pscustomobject]@{ VMName = 'dc1'; Status = 'Compliant' }
            [pscustomobject]@{ VMName = 'svr1'; Status = 'NonCompliant' }
        )
    }

    . $PSScriptRoot/../Private/Get-LabSnapshotAge.ps1
    . $PSScriptRoot/../Private/Get-LabVMDiskUsage.ps1
    . $PSScriptRoot/../Private/Get-LabVMMetrics.ps1
}

Describe 'Get-LabSnapshotAge' {
    It 'Returns age in days when snapshots exist' {
        $snapshotDate = (Get-Date).AddDays(-15)
        Mock Get-VMSnapshot {
            return [pscustomobject]@{
                CreationTime = $snapshotDate
            }
        }

        $age = Get-LabSnapshotAge -VMName 'testvm'

        $age | Should -Be 15
    }

    It 'Returns $null when no snapshots exist' {
        Mock Get-VMSnapshot { return $null }

        $age = Get-LabSnapshotAge -VMName 'testvm'

        $age | Should -Be $null
    }

    It 'Returns oldest snapshot age when multiple snapshots exist' {
        $now = Get-Date
        Mock Get-VMSnapshot {
            return @(
                [pscustomobject]@{ CreationTime = $now.AddDays(-5) }
                [pscustomobject]@{ CreationTime = $now.AddDays(-30) }  # oldest
                [pscustomobject]@{ CreationTime = $now.AddDays(-10) }
            )
        }

        $age = Get-LabSnapshotAge -VMName 'testvm'

        $age | Should -Be 30
    }

    It 'Handles Get-VMSnapshot errors gracefully' {
        Mock Get-VMSnapshot { throw "Hyper-V module not available" }

        $age = Get-LabSnapshotAge -VMName 'testvm' -ErrorAction SilentlyContinue

        $age | Should -Be $null
    }
}

Describe 'Get-LabVMDiskUsage' {
    BeforeEach {
        Mock Test-Path { return $true }
    }

    It 'Returns disk usage for single VHD' {
        Mock Get-VMHardDiskDrive {
            return [pscustomobject]@{ Path = 'C:\VMs\testvm\disk.vhdx' }
        }
        Mock Get-VHD {
            return [pscustomobject]@{
                FileSize = 45GB
                Size = 50GB
            }
        }

        $usage = Get-LabVMDiskUsage -VMName 'testvm'

        $usage.FileSizeGB | Should -Be 45.0
        $usage.SizeGB | Should -Be 50.0
        $usage.UsagePercent | Should -Be 90
    }

    It 'Sums sizes for multiple VHDs' {
        Mock Get-VMHardDiskDrive {
            return @(
                [pscustomobject]@{ Path = 'C:\VMs\testvm\disk1.vhdx' }
                [pscustomobject]@{ Path = 'C:\VMs\testvm\disk2.vhdx' }
            )
        }
        Mock Get-VHD {
            return [pscustomobject]@{
                FileSize = 20GB
                Size = 25GB
            }
        }

        $usage = Get-LabVMDiskUsage -VMName 'testvm'

        $usage.FileSizeGB | Should -Be 40.0
        $usage.SizeGB | Should -Be 50.0
        $usage.UsagePercent | Should -Be 80
    }

    It 'Returns $null when no VHD drives found' {
        Mock Get-VMHardDiskDrive { return $null }

        $usage = Get-LabVMDiskUsage -VMName 'testvm'

        $usage | Should -Be $null
    }

    It 'Handles VHD path not found' {
        Mock Get-VMHardDiskDrive {
            return [pscustomobject]@{ Path = 'C:\VMs\testvm\disk.vhdx' }
        }
        Mock Test-Path { return $false }

        $usage = Get-LabVMDiskUsage -VMName 'testvm'

        $usage | Should -Be $null
    }
}

Describe 'Get-LabVMMetrics' {
    It 'Collects all metrics for a single VM' {
        Mock Get-LabSnapshotAge { return 10 }
        Mock Get-LabVMDiskUsage {
            return [pscustomobject]@{ FileSizeGB = 30; SizeGB = 40; UsagePercent = 75 }
        }

        $metrics = Get-LabVMMetrics -VMName 'dc1'

        $metrics.Count | Should -Be 1
        $metrics[0].VMName | Should -Be 'dc1'
        $metrics[0].SnapshotAge | Should -Be 10
        $metrics[0].DiskUsageGB | Should -Be 30
        $metrics[0].DiskUsagePercent | Should -Be 75
        $metrics[0].UptimeHours | Should -Be 5.5
        $metrics[0].STIGStatus | Should -Be 'Compliant'
    }

    It 'Returns Unknown STIG status for VM not in cache' {
        Mock Get-LabSnapshotAge { return $null }
        Mock Get-LabVMDiskUsage { return $null }

        $metrics = Get-LabVMMetrics -VMName 'ws1'

        $metrics[0].STIGStatus | Should -Be 'Unknown'
    }

    It 'Accepts pipeline input for multiple VMs' {
        Mock Get-LabSnapshotAge { return 5 }
        Mock Get-LabVMDiskUsage {
            return [pscustomobject]@{ FileSizeGB = 20; SizeGB = 25; UsagePercent = 80 }
        }

        $metrics = 'dc1', 'svr1', 'ws1' | Get-LabVMMetrics

        $metrics.Count | Should -Be 3
    }

    It 'Handles collection errors gracefully' {
        Mock Get-LabSnapshotAge { throw "VM not found" }
        Mock Get-LabVMDiskUsage { return $null }

        $metrics = Get-LabVMMetrics -VMName 'badvm' -ErrorAction SilentlyContinue

        $metrics[0].VMName | Should -Be 'badvm'
        $metrics[0].SnapshotAge | Should -Be $null
        $metrics[0].DiskUsageGB | Should -Be $null
        $metrics[0].STIGStatus | Should -Be 'Unknown'
    }
}
