# Get-LabADMXConfig tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabADMXConfig.ps1')
}

Describe 'Get-LabADMXConfig' {
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

        $result = Get-LabADMXConfig

        $result.Enabled | Should -BeTrue
        $result.CreateBaselineGPO | Should -BeFalse
        # PowerShell PSCustomObject converts empty arrays to null
        # Consumers should treat null and empty array equivalently
        if ($null -eq $result.ThirdPartyADMX) {
            $result.ThirdPartyADMX | Should -BeNullOrEmpty
        } else {
            $result.ThirdPartyADMX | Should -BeOfType [array]
            $result.ThirdPartyADMX.Count | Should -Be 0
        }
    }

    It 'returns defaults when GlobalLabConfig exists but has no ADMX key' {
        $script:GlobalLabConfig = @{
            Lab = @{ Name = 'TestLab' }
        }

        $result = Get-LabADMXConfig

        $result.Enabled | Should -BeTrue
        $result.CreateBaselineGPO | Should -BeFalse
        if ($null -eq $result.ThirdPartyADMX) {
            $result.ThirdPartyADMX | Should -BeNullOrEmpty
        } else {
            $result.ThirdPartyADMX | Should -BeOfType [array]
            $result.ThirdPartyADMX.Count | Should -Be 0
        }
    }

    It 'returns defaults when ADMX block exists but is empty hashtable' {
        $script:GlobalLabConfig = @{
            ADMX = @{}
        }

        $result = Get-LabADMXConfig

        $result.Enabled | Should -BeTrue
        $result.CreateBaselineGPO | Should -BeFalse
        if ($null -eq $result.ThirdPartyADMX) {
            $result.ThirdPartyADMX | Should -BeNullOrEmpty
        } else {
            $result.ThirdPartyADMX | Should -BeOfType [array]
            $result.ThirdPartyADMX.Count | Should -Be 0
        }
    }

    It 'returns operator values when all ADMX keys are present' {
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled            = $false
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @(@{ Name = 'Chrome'; Path = 'C:\ADMX\Chrome' })
            }
        }

        $result = Get-LabADMXConfig

        $result.Enabled | Should -BeFalse
        $result.CreateBaselineGPO | Should -BeTrue
        $result.ThirdPartyADMX.Count | Should -Be 1
        $result.ThirdPartyADMX[0].Name | Should -Be 'Chrome'
    }

    It 'returns partial defaults when only some ADMX keys are present' {
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled = $false
            }
        }

        $result = Get-LabADMXConfig

        $result.Enabled | Should -BeFalse
        $result.CreateBaselineGPO | Should -BeFalse
        if ($null -eq $result.ThirdPartyADMX) {
            $result.ThirdPartyADMX | Should -BeNullOrEmpty
        } else {
            $result.ThirdPartyADMX.Count | Should -Be 0
        }
    }

    It 'casts types correctly' {
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled            = 1
                CreateBaselineGPO  = 0
                ThirdPartyADMX     = @()
            }
        }

        $result = Get-LabADMXConfig

        $result.Enabled | Should -BeOfType [bool]
        $result.CreateBaselineGPO | Should -BeOfType [bool]
        $result.Enabled | Should -BeTrue
        $result.CreateBaselineGPO | Should -BeFalse
    }

    It 'does not throw under Set-StrictMode -Version Latest with missing keys' {
        Set-StrictMode -Version Latest
        try {
            $script:GlobalLabConfig = @{
                ADMX = @{
                    Enabled = $true
                }
            }

            { Get-LabADMXConfig } | Should -Not -Throw

            $result = Get-LabADMXConfig
            $result.CreateBaselineGPO | Should -BeFalse
            if ($null -eq $result.ThirdPartyADMX) {
                $result.ThirdPartyADMX | Should -BeNullOrEmpty
            } else {
                $result.ThirdPartyADMX.Count | Should -Be 0
            }
        }
        finally {
            Set-StrictMode -Off
        }
    }

    It 'parses ThirdPartyADMX array correctly' {
        $script:GlobalLabConfig = @{
            ADMX = @{
                ThirdPartyADMX = @(@{ Name = 'Chrome'; Path = 'C:\ADMX\Chrome' })
            }
        }

        $result = Get-LabADMXConfig

        $result.ThirdPartyADMX.Count | Should -Be 1
        $result.ThirdPartyADMX[0].Name | Should -Be 'Chrome'
        $result.ThirdPartyADMX[0].Path | Should -Be 'C:\ADMX\Chrome'
    }

    It 'returns empty array for ThirdPartyADMX when key is absent' {
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled = $false
            }
        }

        $result = Get-LabADMXConfig

        # PowerShell PSCustomObject converts empty arrays to null
        # Consumers should treat null and empty array equivalently
        if ($null -eq $result.ThirdPartyADMX) {
            $result.ThirdPartyADMX | Should -BeNullOrEmpty
        } else {
            $result.ThirdPartyADMX | Should -BeOfType [array]
            $result.ThirdPartyADMX.Count | Should -Be 0
        }
    }

    It 'handles ThirdPartyADMX with multiple entries' {
        $script:GlobalLabConfig = @{
            ADMX = @{
                ThirdPartyADMX = @(
                    @{ Name = 'Chrome'; Path = 'C:\ADMX\Chrome' }
                    @{ Name = 'Firefox'; Path = 'C:\ADMX\Firefox' }
                    @{ Name = 'Edge'; Path = 'C:\ADMX\Edge' }
                )
            }
        }

        $result = Get-LabADMXConfig

        $result.ThirdPartyADMX.Count | Should -Be 3
        $result.ThirdPartyADMX[0].Name | Should -Be 'Chrome'
        $result.ThirdPartyADMX[1].Name | Should -Be 'Firefox'
        $result.ThirdPartyADMX[2].Name | Should -Be 'Edge'
    }
}
