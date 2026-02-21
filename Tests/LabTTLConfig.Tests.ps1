# Get-LabTTLConfig tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabTTLConfig.ps1')
}

Describe 'Get-LabTTLConfig' {
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

        $result = Get-LabTTLConfig

        $result.Enabled | Should -BeFalse
        $result.IdleMinutes | Should -Be 0
        $result.WallClockHours | Should -Be 8
        $result.Action | Should -Be 'Suspend'
    }

    It 'returns defaults when GlobalLabConfig exists but has no TTL key' {
        $script:GlobalLabConfig = @{
            Lab = @{ Name = 'TestLab' }
        }

        $result = Get-LabTTLConfig

        $result.Enabled | Should -BeFalse
        $result.IdleMinutes | Should -Be 0
        $result.WallClockHours | Should -Be 8
        $result.Action | Should -Be 'Suspend'
    }

    It 'returns defaults when TTL block exists but is empty hashtable' {
        $script:GlobalLabConfig = @{
            TTL = @{}
        }

        $result = Get-LabTTLConfig

        $result.Enabled | Should -BeFalse
        $result.IdleMinutes | Should -Be 0
        $result.WallClockHours | Should -Be 8
        $result.Action | Should -Be 'Suspend'
    }

    It 'returns operator values when all TTL keys are present' {
        $script:GlobalLabConfig = @{
            TTL = @{
                Enabled        = $true
                IdleMinutes    = 30
                WallClockHours = 4
                Action         = 'Off'
            }
        }

        $result = Get-LabTTLConfig

        $result.Enabled | Should -BeTrue
        $result.IdleMinutes | Should -Be 30
        $result.WallClockHours | Should -Be 4
        $result.Action | Should -Be 'Off'
    }

    It 'returns partial defaults when only some TTL keys are present' {
        $script:GlobalLabConfig = @{
            TTL = @{
                Enabled = $true
            }
        }

        $result = Get-LabTTLConfig

        $result.Enabled | Should -BeTrue
        $result.IdleMinutes | Should -Be 0
        $result.WallClockHours | Should -Be 8
        $result.Action | Should -Be 'Suspend'
    }

    It 'casts types correctly' {
        $script:GlobalLabConfig = @{
            TTL = @{
                Enabled        = 1
                IdleMinutes    = '45'
                WallClockHours = '12'
                Action         = 'Off'
            }
        }

        $result = Get-LabTTLConfig

        $result.Enabled | Should -BeOfType [bool]
        $result.IdleMinutes | Should -BeOfType [int]
        $result.WallClockHours | Should -BeOfType [int]
        $result.Action | Should -BeOfType [string]
        $result.Enabled | Should -BeTrue
        $result.IdleMinutes | Should -Be 45
        $result.WallClockHours | Should -Be 12
    }

    It 'does not throw under Set-StrictMode -Version Latest with missing keys' {
        Set-StrictMode -Version Latest
        try {
            $script:GlobalLabConfig = @{
                TTL = @{
                    Enabled = $true
                }
            }

            { Get-LabTTLConfig } | Should -Not -Throw

            $result = Get-LabTTLConfig
            $result.IdleMinutes | Should -Be 0
        }
        finally {
            Set-StrictMode -Off
        }
    }
}
