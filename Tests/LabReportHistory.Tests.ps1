BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Write-LabReportMetadata.ps1')
    . (Join-Path $repoRoot 'Public/Get-LabReportHistory.ps1')
    . (Join-Path $repoRoot 'Private/Write-LabAnalyticsEvent.ps1')
    . (Join-Path $repoRoot 'Public/Get-LabAnalytics.ps1')

    $GlobalLabConfig = @{
        Lab = @{
            LabName = 'TestLab'
        }
    }
}

Describe 'Write-LabReportMetadata' {
    BeforeEach {
        Mock Write-LabAnalyticsEvent {}
    }

    It 'Tracks compliance report generation' {
        Write-LabReportMetadata -ReportType Compliance -Format Html -OutputPath 'test.html' -LabName 'TestLab'

        Should -Invoke Write-LabAnalyticsEvent -Times 1 -Exactly -ParameterFilter {
            $EventType -eq 'ReportCompliance' -and
            $LabName -eq 'TestLab' -and
            $Metadata.Format -eq 'Html' -and
            $Metadata.OutputPath -eq 'test.html'
        }
    }

    It 'Tracks resource report generation' {
        Write-LabReportMetadata -ReportType Resource -Format Csv -OutputPath 'test.csv' -LabName 'TestLab'

        Should -Invoke Write-LabAnalyticsEvent -Times 1 -Exactly -ParameterFilter {
            $EventType -eq 'ReportResource' -and
            $Metadata.Format -eq 'Csv'
        }
    }

    It 'Includes summary statistics in metadata' {
        $summary = @{
            TotalVMs = 5
            AvgCPU = 45.0
        }

        Write-LabReportMetadata -ReportType Resource -Format Json -OutputPath 'test.json' -LabName 'TestLab' -Summary $summary

        Should -Invoke Write-LabAnalyticsEvent -Times 1 -Exactly -ParameterFilter {
            $Metadata.TotalVMs -eq 5 -and
            $Metadata.AvgCPU -eq 45.0
        }
    }

    It 'Sets Scheduled flag when specified' {
        Write-LabReportMetadata -ReportType Compliance -Format Html -OutputPath 'test.html' -LabName 'TestLab' -Scheduled

        Should -Invoke Write-LabAnalyticsEvent -Times 1 -Exactly -ParameterFilter {
            $Metadata.Scheduled -eq $true
        }
    }

    It 'Handles missing summary gracefully' {
        { Write-LabReportMetadata -ReportType Compliance -Format Console -OutputPath '' -LabName 'TestLab' } | Should -Not -Throw
    }
}

Describe 'Get-LabReportHistory' {
    BeforeEach {
        $testEvents = @(
            [pscustomobject]@{
                Timestamp = '2026-02-21T10:00:00'
                EventType = 'ReportCompliance'
                LabName = 'TestLab'
                VMNames = @('dc1', 'svr1')
                Metadata = @{
                    Format = 'Html'
                    OutputPath = 'report.html'
                    Scheduled = $false
                    TotalVMs = 2
                    ComplianceRate = 85.0
                }
                Host = 'HOST01'
                User = 'DOMAIN\user'
            }
            [pscustomobject]@{
                Timestamp = '2026-02-21T11:00:00'
                EventType = 'ReportResource'
                LabName = 'TestLab'
                VMNames = @()
                Metadata = @{
                    Format = 'Csv'
                    OutputPath = 'resources.csv'
                    Scheduled = $false
                    TotalVMs = 3
                    AvgCPU = 50.0
                }
                Host = 'HOST01'
                User = 'DOMAIN\user'
            }
        )

        Mock Get-LabAnalytics { return $testEvents }
    }

    It 'Returns all report events when no filters specified' {
        $history = Get-LabReportHistory

        $history | Should -HaveCount 2
    }

    It 'Filters by report type' {
        $history = Get-LabReportHistory -ReportType Compliance

        $history | Should -HaveCount 1
        $history[0].ReportType | Should -Be 'Compliance'
    }

    It 'Returns enriched objects with summary statistics' {
        $history = Get-LabReportHistory -ReportType Compliance

        $history[0].Summary | Should -Not -BeNullOrEmpty
        $history[0].Summary.TotalVMs | Should -Be 2
        $history[0].Summary.ComplianceRate | Should -Be 85.0
    }

    It 'Sorts results by timestamp descending' {
        $history = Get-LabReportHistory

        $history[0].GeneratedAt | Should -Be '2026-02-21T11:00:00'
        $history[-1].GeneratedAt | Should -Be '2026-02-21T10:00:00'
    }
}
