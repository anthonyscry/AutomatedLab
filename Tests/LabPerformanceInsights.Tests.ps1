Describe 'LabPerformanceInsights' {
    BeforeAll {
        $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
        Import-Module $modulePath -Force

        $repoRoot = Split-Path -Parent $PSScriptRoot

        . "$repoRoot\Private\Get-LabPerformanceConfig.ps1"
        . "$repoRoot\Private\Get-LabPerformanceBaseline.ps1"
        . "$repoRoot\Private\Get-LabPerformanceInsights.ps1"
        . "$repoRoot\Public\Get-LabPerformanceRecommendation.ps1"

        $testStoragePath = Join-Path $TestDrive 'insights-performance.json'
    }

    BeforeEach {
        if (Test-Path $testStoragePath) {
            Remove-Item $testStoragePath -Force
        }

        $originalConfig = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Clone() } else { $null }
        $GlobalLabConfig = @{
            Performance = @{
                Enabled       = $true
                StoragePath   = $testStoragePath
                RetentionDays = 90
            }
        }

        # Create test metrics with historical and recent data
        $historicalDate = (Get-Date).AddDays(-10)
        $recentDate = (Get-Date).AddMinutes(-10)

        $testMetrics = @{
            metrics = @(
                # Historical baseline data (fast VMStarts)
                @{ Timestamp = $historicalDate.ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $historicalDate.AddMinutes(1).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5500; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $historicalDate.AddMinutes(2).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $historicalDate.AddMinutes(3).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $historicalDate.AddMinutes(4).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6500; Success = $true; Metadata = $null; Host = 'TEST' }
                # Recent degraded data (slow VMStarts)
                @{ Timestamp = $recentDate.ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 15000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(1).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 16000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(2).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 14000; Success = $true; Metadata = $null; Host = 'TEST' }
                # High failure rate data
                @{ Timestamp = $recentDate.AddMinutes(3).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $false; Metadata = @{ Error = 'Timeout' }; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(4).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $false; Metadata = @{ Error = 'Timeout' }; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(5).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $false; Metadata = @{ Error = 'Timeout' }; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(6).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                # Slow operation for optimization opportunity
                @{ Timestamp = $recentDate.AddMinutes(7).ToString('o'); Operation = 'LabDeploy'; VMName = ''; Duration = 120000; Success = $true; Metadata = $null; Host = 'TEST' }
            )
        }

        $testMetrics | ConvertTo-Json -Depth 8 | Set-Content -Path $testStoragePath -Encoding UTF8
    }

    AfterEach {
        if (Test-Path $testStoragePath) {
            Remove-Item $testStoragePath -Force
        }

        if ($null -ne $originalConfig) {
            $GlobalLabConfig = $originalConfig
        }
    }

    Context 'Get-LabPerformanceBaseline' {
        It 'Calculates baseline from metrics' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $baseline = Get-LabPerformanceBaseline -Metrics $data.metrics

            $baseline.Count | Should -BeGreaterThan 0
            $baseline[0].PSObject.Properties.Name -contains 'BaselineMs' | Should -BeTrue
        }

        It 'Uses p50 (median) as baseline value' {
            # Create test data with known values
            $testData = @(
                @{ Timestamp = (Get-Date).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(1).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5500; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(2).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(3).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(4).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6500; Success = $true; Metadata = $null; Host = 'TEST' }
            )
            $baseline = Get-LabPerformanceBaseline -Metrics $testData -Operation 'VMStart' -VMName 'dc1'

            $baseline.Count | Should -Be 1
            $baseline[0].BaselineMs | Should -Be 5500
        }

        It 'Calculates threshold at p90' {
            # Create test data with known values - sorted: 5000, 5000, 5500, 6000, 6500
            # With 5 elements, p90 index = floor(4 * 0.90) = 3, value = 6000
            $testData = @(
                @{ Timestamp = (Get-Date).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(1).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5500; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(2).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(3).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(4).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6500; Success = $true; Metadata = $null; Host = 'TEST' }
            )
            $baseline = Get-LabPerformanceBaseline -Metrics $testData -Operation 'VMStart' -VMName 'dc1'

            # p90 should be 6000 (index 3 in sorted array)
            $baseline[0].ThresholdMs | Should -Be 6000
        }

        It 'Returns empty array for no metrics' {
            $baseline = @() | Get-LabPerformanceBaseline

            $baseline.Count | Should -Be 0
        }

        It 'Filters by operation type' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $baseline = Get-LabPerformanceBaseline -Metrics $data.metrics -Operation 'VMStart'

            $baseline.Count | Should -Be 1
        }

        It 'Groups by operation and VM name' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $baseline = Get-LabPerformanceBaseline -Metrics $data.metrics

            $baseline.Count | Should -Be 3
        }
    }

    Context 'Get-LabPerformanceInsights' {
        It 'Detects performance degradation' {
            # Create test data with clear degradation
            $oldDate = (Get-Date).AddDays(-10)
            $newDate = (Get-Date).AddMinutes(-10)

            $testData = @(
                @{ Timestamp = $oldDate.ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $oldDate.AddMinutes(1).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5500; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $oldDate.AddMinutes(2).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $newDate.ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 25000; Success = $true; Metadata = $null; Host = 'TEST' }
            )

            $baseline = Get-LabPerformanceBaseline -Metrics $testData
            $insights = Get-LabPerformanceInsights -Metrics $testData -Baseline $baseline -RecentHours 24

            $degradation = $insights | Where-Object { $_.InsightType -eq 'PerformanceDegradation' }
            $degradation.Count | Should -BeGreaterThan 0
        }

        It 'Detects high failure rate' {
            # Create test data with high failure rate (but under critical threshold)
            # Need at least 10% for Warning, 25% for Critical
            # 2 failures out of 11 = ~18% which is Warning range
            $recentDate = (Get-Date).AddMinutes(-10)

            $testData = @(
                @{ Timestamp = $recentDate.ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $false; Metadata = @{ Error = 'Timeout' }; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(1).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $false; Metadata = @{ Error = 'Timeout' }; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(2).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(3).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(4).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(5).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(6).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(7).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(8).ToString('o'); Operation = 'VMStop'; VMName = 'svr1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
            )

            $insights = Get-LabPerformanceInsights -Metrics $testData -RecentHours 24

            $failures = $insights | Where-Object { $_.InsightType -eq 'HighFailureRate' }
            $failures.Count | Should -BeGreaterThan 0
            # 2/9 = 22% which is Warning (under 25% Critical threshold)
            $failures[0].Severity | Should -Be 'Warning'
        }

        It 'Identifies optimization opportunities' {
            # Create test data with slow operation
            $recentDate = (Get-Date).AddMinutes(-10)

            $testData = @(
                @{ Timestamp = $recentDate.ToString('o'); Operation = 'LabDeploy'; VMName = ''; Duration = 120000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $recentDate.AddMinutes(1).ToString('o'); Operation = 'LabDeploy'; VMName = ''; Duration = 130000; Success = $true; Metadata = $null; Host = 'TEST' }
            )

            $insights = Get-LabPerformanceInsights -Metrics $testData -RecentHours 24

            $optimization = $insights | Where-Object { $_.InsightType -eq 'OptimizationOpportunity' }
            $optimization.Count | Should -BeGreaterThan 0
        }

        It 'Returns insights sorted by severity' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $insights = Get-LabPerformanceInsights -Metrics $data.metrics -RecentHours 24

            if ($insights.Count -gt 1) {
                $severities = @('Critical', 'Warning', 'Info')
                $firstSeverity = $severities.IndexOf($insights[0].Severity)
                $lastSeverity = $severities.IndexOf($insights[-1].Severity)
                $firstSeverity -le $lastSeverity | Should -BeTrue
            }
        }

        It 'Returns empty array for no metrics' {
            $insights = @() | Get-LabPerformanceInsights

            $insights.Count | Should -Be 0
        }
    }

    Context 'Get-LabPerformanceRecommendation' {
        It 'Returns recommendations based on metrics' {
            $recommendations = Get-LabPerformanceRecommendation -RecentHours 24

            $recommendations.Count | Should -BeGreaterThan 0
            $recommendations[0].PSObject.Properties.Name -contains 'Recommendation' | Should -BeTrue
            $recommendations[0].PSObject.Properties.Name -contains 'Action' | Should -BeTrue
            $recommendations[0].PSObject.Properties.Name -contains 'Priority' | Should -BeTrue
        }

        It 'Filters by operation parameter' {
            $recommendations = Get-LabPerformanceRecommendation -Operation 'VMStart' -RecentHours 24

            foreach ($rec in $recommendations) {
                $rec.Context.Operation | Should -Be 'VMStart'
            }
        }

        It 'Filters by VMName parameter' {
            $recommendations = Get-LabPerformanceRecommendation -VMName 'dc1' -RecentHours 24

            foreach ($rec in $recommendations) {
                $rec.Context.VMName | Should -Be 'dc1'
            }
        }

        It 'Filters by severity parameter' {
            $recommendations = Get-LabPerformanceRecommendation -Severity Warning -RecentHours 24

            foreach ($rec in $recommendations) {
                $rec.Priority | Should -Be 'Warning'
            }
        }

        It 'Returns actionable recommendations' {
            $recommendations = Get-LabPerformanceRecommendation -RecentHours 24

            foreach ($rec in $recommendations) {
                $rec.Recommendation | Should -Not -BeNullOrEmpty
                $rec.Action | Should -Not -BeNullOrEmpty
            }
        }

        It 'Returns empty array when no metrics available' {
            Remove-Item $testStoragePath -Force
            $recommendations = Get-LabPerformanceRecommendation -RecentHours 24

            $recommendations.Count | Should -Be 0
        }

        It 'Includes context information in recommendations' {
            $recommendations = Get-LabPerformanceRecommendation -RecentHours 24

            foreach ($rec in $recommendations) {
                $rec.Context.Message | Should -Not -BeNullOrEmpty
                $rec.Context.Details | Should -Not -BeNullOrEmpty
            }
        }
    }
}
