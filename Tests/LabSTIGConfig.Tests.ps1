# Get-LabSTIGConfig tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabSTIGConfig.ps1')
}

Describe 'Get-LabSTIGConfig' {
    AfterEach {
        # Clean up GlobalLabConfig between tests
        if (Test-Path variable:GlobalLabConfig) {
            Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'returns defaults when GlobalLabConfig variable does not exist' {
        # Ensure variable is absent
        if (Test-Path variable:GlobalLabConfig) {
            Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue
        }

        $result = Get-LabSTIGConfig

        $result.Enabled | Should -BeFalse
        $result.AutoApplyOnDeploy | Should -BeTrue
        $result.ComplianceCachePath | Should -Be '.planning/stig-compliance.json'
        $result.Exceptions | Should -BeOfType [hashtable]
        $result.Exceptions.Count | Should -Be 0
    }

    It 'returns defaults when GlobalLabConfig exists but has no STIG key' {
        $script:GlobalLabConfig = @{
            Lab = @{ Name = 'TestLab' }
        }

        $result = Get-LabSTIGConfig

        $result.Enabled | Should -BeFalse
        $result.AutoApplyOnDeploy | Should -BeTrue
        $result.ComplianceCachePath | Should -Be '.planning/stig-compliance.json'
        $result.Exceptions | Should -BeOfType [hashtable]
        $result.Exceptions.Count | Should -Be 0
    }

    It 'returns defaults when STIG block exists but is empty hashtable' {
        $script:GlobalLabConfig = @{
            STIG = @{}
        }

        $result = Get-LabSTIGConfig

        $result.Enabled | Should -BeFalse
        $result.AutoApplyOnDeploy | Should -BeTrue
        $result.ComplianceCachePath | Should -Be '.planning/stig-compliance.json'
        $result.Exceptions | Should -BeOfType [hashtable]
        $result.Exceptions.Count | Should -Be 0
    }

    It 'returns operator values when all STIG keys are present' {
        $script:GlobalLabConfig = @{
            STIG = @{
                Enabled             = $true
                AutoApplyOnDeploy   = $false
                ComplianceCachePath = 'C:\custom\stig.json'
                Exceptions          = @{ 'dc1' = @('V-12345') }
            }
        }

        $result = Get-LabSTIGConfig

        $result.Enabled | Should -BeTrue
        $result.AutoApplyOnDeploy | Should -BeFalse
        $result.ComplianceCachePath | Should -Be 'C:\custom\stig.json'
        $result.Exceptions['dc1'] | Should -Contain 'V-12345'
    }

    It 'returns partial defaults when only some STIG keys are present' {
        $script:GlobalLabConfig = @{
            STIG = @{
                Enabled = $true
            }
        }

        $result = Get-LabSTIGConfig

        $result.Enabled | Should -BeTrue
        $result.AutoApplyOnDeploy | Should -BeTrue
        $result.ComplianceCachePath | Should -Be '.planning/stig-compliance.json'
        $result.Exceptions.Count | Should -Be 0
    }

    It 'casts types correctly' {
        $script:GlobalLabConfig = @{
            STIG = @{
                Enabled             = 1
                AutoApplyOnDeploy   = 0
                ComplianceCachePath = 42
                Exceptions          = @{}
            }
        }

        $result = Get-LabSTIGConfig

        $result.Enabled | Should -BeOfType [bool]
        $result.AutoApplyOnDeploy | Should -BeOfType [bool]
        $result.ComplianceCachePath | Should -BeOfType [string]
        $result.Exceptions | Should -BeOfType [hashtable]
        $result.Enabled | Should -BeTrue
        $result.AutoApplyOnDeploy | Should -BeFalse
        $result.ComplianceCachePath | Should -Be '42'
    }

    It 'does not throw under Set-StrictMode -Version Latest with missing keys' {
        Set-StrictMode -Version Latest
        try {
            $script:GlobalLabConfig = @{
                STIG = @{
                    Enabled = $true
                }
            }

            { Get-LabSTIGConfig } | Should -Not -Throw

            $result = Get-LabSTIGConfig
            $result.AutoApplyOnDeploy | Should -BeTrue
            $result.ComplianceCachePath | Should -Be '.planning/stig-compliance.json'
        }
        finally {
            Set-StrictMode -Off
        }
    }

    It 'parses Exceptions hashtable with per-VM V-number arrays correctly' {
        $script:GlobalLabConfig = @{
            STIG = @{
                Exceptions = @{
                    'dc1'  = @('V-12345', 'V-67890')
                    'svr1' = @('V-11111')
                }
            }
        }

        $result = Get-LabSTIGConfig

        $result.Exceptions['dc1'] | Should -HaveCount 2
        $result.Exceptions['dc1'] | Should -Contain 'V-12345'
        $result.Exceptions['dc1'] | Should -Contain 'V-67890'
        $result.Exceptions['svr1'] | Should -HaveCount 1
        $result.Exceptions['svr1'] | Should -Contain 'V-11111'
    }

    It 'returns empty hashtable for Exceptions when key is absent' {
        $script:GlobalLabConfig = @{
            STIG = @{
                Enabled = $false
            }
        }

        $result = Get-LabSTIGConfig

        $result.Exceptions | Should -BeOfType [hashtable]
        $result.Exceptions.Count | Should -Be 0
    }

    It 'handles Exceptions with multiple VMs and multiple V-numbers per VM' {
        $script:GlobalLabConfig = @{
            STIG = @{
                Exceptions = @{
                    'dc1'   = @('V-11111', 'V-22222', 'V-33333')
                    'svr1'  = @('V-44444', 'V-55555')
                    'ws1'   = @('V-66666')
                }
            }
        }

        $result = Get-LabSTIGConfig

        $result.Exceptions.Count | Should -Be 3
        $result.Exceptions['dc1'] | Should -HaveCount 3
        $result.Exceptions['svr1'] | Should -HaveCount 2
        $result.Exceptions['ws1'] | Should -HaveCount 1
    }
}
