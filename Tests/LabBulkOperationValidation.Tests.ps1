Describe 'Test-LabBulkOperation' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module "$moduleRoot\SimpleLab\SimpleLab.psd1" -Force

        . "$moduleRoot\Private\Test-LabBulkOperationCore.ps1"
    }

    Context 'Hyper-V module check' {
        It 'Passes when Hyper-V module is available' {
            Mock Get-Module { return $true } -ParameterFilter { $Name -eq 'Hyper-V' }

            $result = Test-LabBulkOperationCore -VMName @('test-vm') -Operation 'Start'

            $result.Checks[0].Name | Should -Be 'Hyper-V Module'
            $result.Checks[0].Status | Should -Be 'Pass'
        }

        It 'Fails when Hyper-V module not found' {
            Mock Get-Module { throw 'Module not found' }

            $result = Test-LabBulkOperationCore -VMName @('test-vm') -Operation 'Start'

            $result.Checks[0].Status | Should -Be 'Fail'
            $result.Checks[0].Remediation | Should -Not -BeNullOrEmpty
            $result.OverallStatus | Should -Be 'Fail'
        }
    }

    Context 'VM existence check' {
        It 'Passes when all VMs exist' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off' } }

            $result = Test-LabBulkOperationCore -VMName @('vm1', 'vm2') -Operation 'Start'

            $vmCheck = $result.Checks | Where-Object { $_.Name -eq 'VM Existence' }
            $vmCheck.Status | Should -Be 'Pass'
        }

        It 'Fails when VMs are missing' {
            Mock Get-Module { return $true }
            Mock Get-VM { throw "VM '$Name' not found" }

            $result = Test-LabBulkOperationCore -VMName @('missing-vm') -Operation 'Start'

            $vmCheck = $result.Checks | Where-Object { $_.Name -eq 'VM Existence' }
            $vmCheck.Status | Should -Be 'Fail'
            $vmCheck.Remediation | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Operation validation' {
        It 'Warns when starting already-running VMs' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Running' } }

            $result = Test-LabBulkOperationCore -VMName @('running-vm') -Operation 'Start'

            $opCheck = $result.Checks | Where-Object { $_.Name -eq 'Operation Validation' }
            $opCheck.Status | Should -Be 'Warn'
        }

        It 'Warns when stopping already-stopped VMs' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off' } }

            $result = Test-LabBulkOperationCore -VMName @('stopped-vm') -Operation 'Stop'

            $opCheck = $result.Checks | Where-Object { $_.Name -eq 'Operation Validation' }
            $opCheck.Status | Should -Be 'Warn'
        }

        It 'Passes operation validation for valid state transitions' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off' } }

            $result = Test-LabBulkOperationCore -VMName @('stopped-vm') -Operation 'Start'

            $opCheck = $result.Checks | Where-Object { $_.Name -eq 'Operation Validation' }
            $opCheck.Status | Should -Be 'Pass'
        }
    }

    Context 'Resource availability check' {
        It 'Skips resource check when CheckResourceAvailability not specified' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off' } }

            $result = Test-LabBulkOperationCore -VMName @('vm1') -Operation 'Start'

            $resourceCheck = $result.Checks | Where-Object { $_.Name -eq 'Resource Availability' }
            $resourceCheck | Should -BeNullOrEmpty
        }

        It 'Includes resource check when CheckResourceAvailability specified' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off'; MemoryGB = 4GB } }
            Mock Get-LabHostResourceInfo { return [pscustomobject]@{ FreeRAMGB = 16 } }

            $result = Test-LabBulkOperationCore -VMName @('vm1') -Operation 'Start' -CheckResourceAvailability

            $resourceCheck = $result.Checks | Where-Object { $_.Name -eq 'Resource Availability' }
            $resourceCheck | Should -Not -BeNullOrEmpty
        }

        It 'Warns when insufficient RAM for Start operation' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off'; MemoryGB = 16GB } }
            Mock Get-LabHostResourceInfo { return [pscustomobject]@{ FreeRAMGB = 8 } }

            $result = Test-LabBulkOperationCore -VMName @('vm1') -Operation 'Start' -CheckResourceAvailability

            $resourceCheck = $result.Checks | Where-Object { $_.Name -eq 'Resource Availability' }
            $resourceCheck.Status | Should -Be 'Warn'
        }
    }

    Context 'Overall status calculation' {
        It 'Returns Fail overall status when any check fails' {
            Mock Get-Module { throw 'Module not found' }

            $result = Test-LabBulkOperationCore -VMName @('vm1') -Operation 'Start'

            $result.OverallStatus | Should -Be 'Fail'
        }

        It 'Returns Warning overall status when checks warn but none fail' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Running' } }

            $result = Test-LabBulkOperationCore -VMName @('running-vm') -Operation 'Start'

            $result.OverallStatus | Should -Be 'Warning'
        }

        It 'Returns OK overall status when all checks pass' {
            Mock Get-Module { return $true }
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off' } }

            $result = Test-LabBulkOperationCore -VMName @('vm1') -Operation 'Start'

            $result.OverallStatus | Should -Be 'OK'
        }
    }
}
