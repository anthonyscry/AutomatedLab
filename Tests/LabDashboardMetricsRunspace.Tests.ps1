# Dashboard Metrics Runspace Lifecycle Tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    
    # Source Private functions
    . (Join-Path $repoRoot 'Private/Get-LabVMMetrics.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabSnapshotAge.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabVMDiskUsage.ps1')
    
    # Mock functions that would normally be loaded
    function Get-LabUptime {
        param($VMName)
        return [pscustomobject]@{
            VMName = $VMName
            ElapsedHours = 5.5
        }
    }
    
    function Get-LabSTIGCompliance {
        return @(
            [pscustomobject]@{
                VMName = 'testvm'
                Status = 'Compliant'
            }
        )
    }
    
    # Mock Hyper-V cmdlets
    Mock Get-VMSnapshot {
        return [pscustomobject]@{
            VMName = 'testvm'
            Name = 'TestSnapshot'
            CreationTime = (Get-Date).AddDays(-10)
        }
    }
    
    Mock Get-VMHardDiskDrive {
        return [pscustomobject]@{
            VMName = 'testvm'
            Path = 'C:\Test\disk.vhdx'
        }
    }
    
    Mock Get-VHD {
        return [pscustomobject]@{
            Path = 'C:\Test\disk.vhdx'
            FileSize = 45GB
            Size = 50GB
        }
    }
}

Describe 'Dashboard Metrics Runspace' {
    It 'Creates synchronized hashtable with Continue flag' {
        $syncHash = [System.Collections.Hashtable]::Synchronized(@{})
        $syncHash['Continue'] = $true
        
        $syncHash.ContainsKey('Continue') | Should -Be $true
        $syncHash['Continue'] | Should -Be $true
        $syncHash.GetType().Name | Should -Be 'SyncHashtable'
    }
    
    It 'Get-LabVMMetrics returns all metrics for a VM' {
        $result = Get-LabVMMetrics -VMName 'testvm'
        
        $result | Should -Not -Be $null
        $result.VMName | Should -Be 'testvm'
        $result.SnapshotAge | Should -Be 10
        $result.DiskUsageGB | Should -Be 45
        $result.DiskUsagePercent | Should -Be 90
        $result.UptimeHours | Should -Be 5.5
        $result.STIGStatus | Should -Be 'Compliant'
    }
    
    It 'Get-LabVMMetrics accepts pipeline input for multiple VMs' {
        $results = 'testvm1', 'testvm2' | Get-LabVMMetrics
        
        $results.Count | Should -Be 2
        $results[0].VMName | Should -Be 'testvm1'
        $results[1].VMName | Should -Be 'testvm2'
    }
    
    It 'Get-LabVMMetrics handles missing VM gracefully' {
        Mock Get-VMSnapshot { return $null } -ParameterFilter { $VMName -eq 'missing' }
        
        $result = Get-LabVMMetrics -VMName 'missing' -ErrorAction SilentlyContinue
        
        # Should return object with null values rather than throwing
        $result | Should -Not -Be $null
        $result.VMName | Should -Be 'missing'
    }
}
