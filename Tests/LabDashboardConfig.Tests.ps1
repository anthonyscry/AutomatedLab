# Get-LabDashboardConfig tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabDashboardConfig.ps1')
}

Describe 'Get-LabDashboardConfig' {
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

        $result = Get-LabDashboardConfig

        $result.SnapshotStaleDays | Should -Be 7
        $result.SnapshotStaleCritical | Should -Be 30
        $result.DiskUsagePercent | Should -Be 80
        $result.DiskUsageCritical | Should -Be 95
        $result.UptimeStaleHours | Should -Be 72
    }

    It 'returns defaults when GlobalLabConfig exists but has no Dashboard key' {
        $script:GlobalLabConfig = @{
            Lab = @{ Name = 'TestLab' }
        }

        $result = Get-LabDashboardConfig

        $result.SnapshotStaleDays | Should -Be 7
        $result.SnapshotStaleCritical | Should -Be 30
        $result.DiskUsagePercent | Should -Be 80
        $result.DiskUsageCritical | Should -Be 95
        $result.UptimeStaleHours | Should -Be 72
    }

    It 'returns defaults when Dashboard block exists but is empty hashtable' {
        $script:GlobalLabConfig = @{
            Dashboard = @{}
        }

        $result = Get-LabDashboardConfig

        $result.SnapshotStaleDays | Should -Be 7
        $result.SnapshotStaleCritical | Should -Be 30
        $result.DiskUsagePercent | Should -Be 80
        $result.DiskUsageCritical | Should -Be 95
        $result.UptimeStaleHours | Should -Be 72
    }

    It 'returns operator values when all Dashboard keys are present' {
        $script:GlobalLabConfig = @{
            Dashboard = @{
                SnapshotStaleDays = 14
                SnapshotStaleCritical = 60
                DiskUsagePercent = 85
                DiskUsageCritical = 98
                UptimeStaleHours = 48
            }
        }

        $result = Get-LabDashboardConfig

        $result.SnapshotStaleDays | Should -Be 14
        $result.SnapshotStaleCritical | Should -Be 60
        $result.DiskUsagePercent | Should -Be 85
        $result.DiskUsageCritical | Should -Be 98
        $result.UptimeStaleHours | Should -Be 48
    }

    It 'returns partial defaults when only some Dashboard keys are present' {
        $script:GlobalLabConfig = @{
            Dashboard = @{
                SnapshotStaleDays = 21
                # Missing SnapshotStaleCritical
                DiskUsagePercent = 90
                # Missing DiskUsageCritical, UptimeStaleHours
            }
        }

        $result = Get-LabDashboardConfig

        $result.SnapshotStaleDays | Should -Be 21
        $result.SnapshotStaleCritical | Should -Be 30  # default
        $result.DiskUsagePercent | Should -Be 90
        $result.DiskUsageCritical | Should -Be 95     # default
        $result.UptimeStaleHours | Should -Be 72      # default
    }

    It 'casts types correctly' {
        $script:GlobalLabConfig = @{
            Dashboard = @{
                SnapshotStaleDays = '5'
                SnapshotStaleCritical = '15'
                DiskUsagePercent = '75'
                DiskUsageCritical = '90'
                UptimeStaleHours = '24'
            }
        }

        $result = Get-LabDashboardConfig

        $result.SnapshotStaleDays | Should -BeOfType [int]
        $result.SnapshotStaleCritical | Should -BeOfType [int]
        $result.DiskUsagePercent | Should -BeOfType [int]
        $result.DiskUsageCritical | Should -BeOfType [int]
        $result.UptimeStaleHours | Should -BeOfType [int]
        $result.SnapshotStaleDays | Should -Be 5
        $result.SnapshotStaleCritical | Should -Be 15
        $result.DiskUsagePercent | Should -Be 75
        $result.DiskUsageCritical | Should -Be 90
        $result.UptimeStaleHours | Should -Be 24
    }

    It 'does not throw under Set-StrictMode -Version Latest with missing keys' {
        Set-StrictMode -Version Latest
        try {
            $script:GlobalLabConfig = @{
                Dashboard = @{
                    SnapshotStaleDays = 21
                }
            }

            { Get-LabDashboardConfig } | Should -Not -Throw

            $result = Get-LabDashboardConfig
            $result.SnapshotStaleCritical | Should -Be 30
        }
        finally {
            Set-StrictMode -Off
        }
    }
}
