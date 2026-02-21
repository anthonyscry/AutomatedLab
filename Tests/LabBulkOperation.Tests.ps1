Describe 'Invoke-LabBulkOperation' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module "$moduleRoot\SimpleLab\SimpleLab.psd1" -Force

        . "$moduleRoot\Private\Invoke-LabBulkOperationCore.ps1"

        $mockVMs = @(
            @{ Name = 'test-vm1'; State = 'Off' }
            @{ Name = 'test-vm2'; State = 'Running' }
            @{ Name = 'test-vm3'; State = 'Off' }
        )
    }

    Context 'Sequential execution' {
        It 'Processes all VMs sequentially when Parallel not specified' {
            Mock Get-VM {
                $state = switch ($Name) {
                    'test-vm1' { 'Off' }
                    'test-vm2' { 'Running' }
                    'test-vm3' { 'Off' }
                }
                return [pscustomobject]@{ Name = $Name; State = $state }
            }

            Mock Start-VM { return $null }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1', 'test-vm3') -Operation 'Start'

            $result.OperationCount | Should -Be 2
            $result.Parallel | Should -BeFalse
        }

        It 'Returns success results for successful operations' {
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Off' } }
            Mock Start-VM { return $null }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1') -Operation 'Start'

            $result.Success.Count | Should -Be 1
            $result.Success[0] | Should -Be 'test-vm1'
        }

        It 'Returns skipped results for already-running VMs on start' {
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Running' } }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm2') -Operation 'Start'

            $result.Skipped.Count | Should -Be 1
            $result.Skipped[0] | Should -Match 'test-vm2.*Already running'
        }
    }

    Context 'Parallel execution' {
        It 'Processes VMs in parallel when Parallel specified' {
            Mock Get-VM {
                $state = switch ($Name) {
                    'test-vm1' { 'Off' }
                    'test-vm2' { 'Off' }
                    'test-vm3' { 'Off' }
                }
                return [pscustomobject]@{ Name = $Name; State = $state }
            }
            Mock Start-VM { Start-Sleep -Milliseconds 100; return $null }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1', 'test-vm2', 'test-vm3') -Operation 'Start' -Parallel

            $result.Parallel | Should -BeTrue
            $result.Success.Count | Should -Be 3
        }
    }

    Context 'Error handling' {
        It 'Continues processing after individual VM failure' {
            Mock Get-VM {
                if ($Name -eq 'test-vm1') {
                    throw 'VM not found'
                }
                return [pscustomobject]@{ Name = $Name; State = 'Off' }
            }
            Mock Start-VM { return $null }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1', 'test-vm2') -Operation 'Start'

            $result.Failed.Count | Should -Be 1
            $result.Success.Count | Should -Be 1
            $result.OverallStatus | Should -Be 'Partial'
        }

        It 'Returns Failed overall status when all operations fail' {
            Mock Get-VM { throw 'All VMs not found' }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1', 'test-vm2') -Operation 'Start'

            $result.OverallStatus | Should -Be 'Failed'
            $result.Failed.Count | Should -Be 2
        }
    }

    Context 'Operation types' {
        It 'Supports Stop operation' {
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Running' } }
            Mock Stop-VM { return $null }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1') -Operation 'Stop'

            $result.Operation | Should -Be 'Stop'
            $result.Success.Count | Should -Be 1
            Should -Invoke Stop-VM -Times 1
        }

        It 'Supports Suspend operation' {
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Running' } }
            Mock Suspend-VM { return $null }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1') -Operation 'Suspend'

            $result.Operation | Should -Be 'Suspend'
            $result.Success.Count | Should -Be 1
        }

        It 'Supports Restart operation' {
            Mock Get-VM { return [pscustomobject]@{ Name = $Name; State = 'Running' } }
            Mock Restart-VM { return $null }

            $result = Invoke-LabBulkOperationCore -VMName @('test-vm1') -Operation 'Restart'

            $result.Operation | Should -Be 'Restart'
            $result.Success.Count | Should -Be 1
        }
    }
}
