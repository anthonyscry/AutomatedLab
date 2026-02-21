Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabSTIGConfig.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabSTIGBaselineCore.ps1')
    . (Join-Path $repoRoot 'Public/Invoke-LabSTIGBaseline.ps1')
}

Describe 'Invoke-LabSTIGBaseline (Public)' {

    Context 'Parameter routing - single VM' {

        It 'Calls Invoke-LabSTIGBaselineCore with correct -VMName when -VMName specified' {
            $script:coreCallArgs = $null
            Mock Invoke-LabSTIGBaselineCore {
                param([string[]]$VMName, [string]$ComplianceCachePath)
                $script:coreCallArgs = @{ VMName = $VMName; ComplianceCachePath = $ComplianceCachePath }
                [pscustomobject]@{ VMsProcessed = 1; VMsSucceeded = 1; VMsFailed = 0; Repairs = @(); RemainingIssues = @(); DurationSeconds = 0 }
            }

            Invoke-LabSTIGBaseline -VMName 'dc1'

            $script:coreCallArgs | Should -Not -BeNullOrEmpty
            $script:coreCallArgs.VMName | Should -Contain 'dc1'
        }

        It 'Calls Invoke-LabSTIGBaselineCore with multiple VM names when array supplied' {
            $script:coreCallArgs = $null
            Mock Invoke-LabSTIGBaselineCore {
                param([string[]]$VMName, [string]$ComplianceCachePath)
                $script:coreCallArgs = @{ VMName = $VMName }
                [pscustomobject]@{ VMsProcessed = 2; VMsSucceeded = 2; VMsFailed = 0; Repairs = @(); RemainingIssues = @(); DurationSeconds = 0 }
            }

            Invoke-LabSTIGBaseline -VMName @('dc1', 'svr1')

            $script:coreCallArgs.VMName | Should -Contain 'dc1'
            $script:coreCallArgs.VMName | Should -Contain 'svr1'
        }
    }

    Context 'Parameter routing - all VMs' {

        It 'Calls Invoke-LabSTIGBaselineCore with no VMName parameter when -VMName not specified' {
            $script:coreCalledWithNoVMName = $false
            Mock Invoke-LabSTIGBaselineCore {
                param([string[]]$VMName, [string]$ComplianceCachePath)
                # When called with no VMName (empty/default), VMName should be empty
                if ($null -eq $VMName -or $VMName.Count -eq 0) {
                    $script:coreCalledWithNoVMName = $true
                }
                [pscustomobject]@{ VMsProcessed = 0; VMsSucceeded = 0; VMsFailed = 0; Repairs = @(); RemainingIssues = @(); DurationSeconds = 0 }
            }

            Invoke-LabSTIGBaseline

            $script:coreCalledWithNoVMName | Should -Be $true
        }
    }

    Context 'Return value passthrough' {

        It 'Returns the PSCustomObject result from Invoke-LabSTIGBaselineCore' {
            $expectedResult = [pscustomobject]@{
                VMsProcessed    = 3
                VMsSucceeded    = 2
                VMsFailed       = 1
                Repairs         = @('vm1:stig_applied', 'vm2:stig_applied')
                RemainingIssues = @('vm3:failed')
                DurationSeconds = 42
            }
            Mock Invoke-LabSTIGBaselineCore { $expectedResult }

            $result = Invoke-LabSTIGBaseline -VMName 'vm1'

            $result.VMsProcessed    | Should -Be 3
            $result.VMsSucceeded    | Should -Be 2
            $result.VMsFailed       | Should -Be 1
            $result.DurationSeconds | Should -Be 42
        }

        It 'Returns PSCustomObject (not wrapped in array)' {
            Mock Invoke-LabSTIGBaselineCore {
                [pscustomobject]@{ VMsProcessed = 1; VMsSucceeded = 1; VMsFailed = 0; Repairs = @(); RemainingIssues = @(); DurationSeconds = 0 }
            }

            $result = Invoke-LabSTIGBaseline -VMName 'dc1'

            $result.GetType().Name | Should -Be 'PSCustomObject'
        }
    }

    Context 'Comment-based help' {

        It 'Has .SYNOPSIS defined' {
            $help = Get-Help Invoke-LabSTIGBaseline -ErrorAction SilentlyContinue
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Has .DESCRIPTION defined' {
            $help = Get-Help Invoke-LabSTIGBaseline -Full -ErrorAction SilentlyContinue
            $help.description | Should -Not -BeNullOrEmpty
        }

        It 'Has -VMName parameter documented' {
            $help = Get-Help Invoke-LabSTIGBaseline -Parameter VMName -ErrorAction SilentlyContinue
            $help | Should -Not -BeNullOrEmpty
        }

        It 'Has at least one .EXAMPLE defined' {
            $help = Get-Help Invoke-LabSTIGBaseline -Full -ErrorAction SilentlyContinue
            $help.examples.example.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Verbose passthrough' {

        It 'Supports -Verbose switch without error' {
            Mock Invoke-LabSTIGBaselineCore {
                [pscustomobject]@{ VMsProcessed = 0; VMsSucceeded = 0; VMsFailed = 0; Repairs = @(); RemainingIssues = @(); DurationSeconds = 0 }
            }

            # Should not throw when -Verbose is specified
            { Invoke-LabSTIGBaseline -VMName 'dc1' -Verbose } | Should -Not -Throw
        }
    }

    Context 'STIG disabled early return' {

        It 'Returns empty-like no-op result when STIG feature is disabled' {
            Mock Invoke-LabSTIGBaselineCore {
                [pscustomobject]@{ VMsProcessed = 0; VMsSucceeded = 0; VMsFailed = 0; Repairs = @(); RemainingIssues = @(); DurationSeconds = 0 }
            }
            Mock Get-LabSTIGConfig {
                [pscustomobject]@{
                    Enabled             = $false
                    AutoApplyOnDeploy   = $true
                    ComplianceCachePath = '.planning/stig-compliance.json'
                    Exceptions          = @{}
                }
            }

            $result = Invoke-LabSTIGBaseline -VMName 'dc1'

            $result.VMsProcessed | Should -Be 0
            $result.VMsFailed    | Should -Be 0
        }
    }
}
