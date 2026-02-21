Describe 'Get-LabUsageTrends' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module "$moduleRoot\SimpleLab\SimpleLab.psd1" -Force

        . "$moduleRoot\Private\Get-LabUsageTrendsCore.ps1"
        . "$moduleRoot\Private\Get-LabAnalyticsConfig.ps1"

        function New-TestAnalyticsEvent {
            param([DateTime]$Timestamp, [string]$EventType, [string]$LabName = 'TestLab')
            [pscustomobject]@{
                Timestamp = $Timestamp.ToString('o')
                EventType = $EventType
                LabName   = $LabName
                VMNames   = @()
                Metadata  = @{ DurationSeconds = 3600 }
                Host      = 'TESTHOST'
                User      = 'TEST\testuser'
            }
        }
    }

    Context 'Day period grouping' {
        It 'Groups events by day correctly' {
            $events = @(
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-01 08:00:00') -EventType 'LabDeployed'
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-01 14:00:00') -EventType 'LabDeployed'
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-02 10:00:00') -EventType 'LabDeployed'
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-02 16:00:00') -EventType 'LabTeardown'
            )

            $result = Get-LabUsageTrendsCore -Events $events -Period 'Day'

            $result.Count | Should -Be 2
            $result[0].Period | Should -Be '2026-02-01'
            $result[0].Deploys | Should -Be 2
            $result[0].Teardowns | Should -Be 0
            $result[1].Period | Should -Be '2026-02-02'
            $result[1].Deploys | Should -Be 1
            $result[1].Teardowns | Should -Be 1
        }

        It 'Calculates total uptime hours correctly' {
            $events = @(
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-01 08:00:00') -EventType 'LabDeployed'
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-01 14:00:00') -EventType 'LabDeployed'
            )

            $result = Get-LabUsageTrendsCore -Events $events -Period 'Day'

            $result[0].TotalUptimeHours | Should -Be 2.0
        }
    }

    Context 'Week period grouping' {
        It 'Groups events by week correctly' {
            $events = @(
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-01 08:00:00') -EventType 'LabDeployed'
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-08 10:00:00') -EventType 'LabDeployed'
            )

            $result = Get-LabUsageTrendsCore -Events $events -Period 'Week'

            $result.Count | Should -Be 2
            $result[0].Period | Should -Match '^\d{4}-W\d{2}$'
        }
    }

    Context 'Month period grouping' {
        It 'Groups events by month correctly' {
            $events = @(
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-01-15 08:00:00') -EventType 'LabDeployed'
                New-TestAnalyticsEvent -Timestamp (Get-Date '2026-02-01 10:00:00') -EventType 'LabDeployed'
            )

            $result = Get-LabUsageTrendsCore -Events $events -Period 'Month'

            $result.Count | Should -Be 2
            $result[0].Period | Should -Be '2026-01'
            $result[1].Period | Should -Be '2026-02'
        }
    }
}
