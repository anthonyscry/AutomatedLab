Describe 'Get-LabPerformanceMetrics' {
    BeforeAll {
        $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
        Import-Module $modulePath -Force

        $repoRoot = Split-Path -Parent $PSScriptRoot

        . "$repoRoot\Private\Get-LabPerformanceConfig.ps1"
        . "$repoRoot\Private\Get-LabPerformanceMetricsCore.ps1"
        . "$repoRoot\Public\Get-LabPerformanceMetrics.ps1"

        $testStoragePath = Join-Path $TestDrive 'query-performance.json'
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

        # Create test metrics
        $testMetrics = @{
            metrics = @(
                @{ Timestamp = (Get-Date).AddMinutes(-10).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(-8).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 6000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(-6).ToString('o'); Operation = 'VMStart'; VMName = 'svr1'; Duration = 8000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(-4).ToString('o'); Operation = 'VMStop'; VMName = 'dc1'; Duration = 2000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = (Get-Date).AddMinutes(-2).ToString('o'); Operation = 'VMStart'; VMName = 'dc1'; Duration = 5500; Success = $false; Metadata = @{ Error = 'Timeout' }; Host = 'TEST' }
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

    Context 'Get-LabPerformanceMetricsCore' {
        It 'Aggregates metrics correctly' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $result = $data.metrics | Get-LabPerformanceMetricsCore

            $result.TotalCount | Should -Be 5
            $result.SuccessCount | Should -Be 4
            $result.FailureCount | Should -Be 1
            $result.Min | Should -Be 2000
            $result.Max | Should -Be 8000
        }

        It 'Calculates average duration correctly' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $result = $data.metrics | Get-LabPerformanceMetricsCore

            $expectedAvg = (5000 + 6000 + 8000 + 2000 + 5500) / 5
            [math]::Round($result.Avg, 2) | Should -Be ([math]::Round($expectedAvg, 2))
        }

        It 'Calculates percentiles correctly' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $result = $data.metrics | Get-LabPerformanceMetricsCore

            $result.Percentile50 | Should -Not -BeNullOrEmpty
            $result.Percentile90 | Should -Not -BeNullOrEmpty
            $result.Percentile95 | Should -Not -BeNullOrEmpty
        }

        It 'Filters by operation type' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $result = $data.metrics | Get-LabPerformanceMetricsCore -Operation 'VMStart'

            $result.TotalCount | Should -Be 4
        }

        It 'Filters by VM name' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $result = $data.metrics | Get-LabPerformanceMetricsCore -VMName 'dc1'

            $result.TotalCount | Should -Be 4
        }

        It 'Filters by success status' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $result = $data.metrics | Get-LabPerformanceMetricsCore -Success $true

            $result.TotalCount | Should -Be 4
            $result.SuccessCount | Should -Be 4
        }

        It 'Calculates success rate percentage' {
            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $result = $data.metrics | Get-LabPerformanceMetricsCore

            $result.SuccessRatePercent | Should -Be 80.0
        }

        It 'Returns empty result for no metrics' {
            $result = @() | Get-LabPerformanceMetricsCore

            $result.TotalCount | Should -Be 0
            $result.Min | Should -BeNullOrEmpty
        }
    }

    Context 'Get-LabPerformanceMetrics public API' {
        It 'Returns aggregated metrics by default' {
            $result = Get-LabPerformanceMetrics

            $result.TotalCount | Should -Be 5
            $result.Avg | Should -Not -BeNullOrEmpty
        }

        It 'Filters by operation parameter' {
            $result = Get-LabPerformanceMetrics -Operation 'VMStart'

            $result.TotalCount | Should -Be 4
        }

        It 'Filters by VMName parameter' {
            $result = Get-LabPerformanceMetrics -VMName 'svr1'

            $result.TotalCount | Should -Be 1
        }

        It 'Filters by Success parameter' {
            $result = Get-LabPerformanceMetrics -Success $false

            $result.TotalCount | Should -Be 1
            $result.FailureCount | Should -Be 1
        }

        It 'Returns raw metrics when Aggregated is false' {
            $result = Get-LabPerformanceMetrics -Aggregated:$false -Last 10

            $result.Count | Should -Be 5
            $result[0].PSObject.Properties.Name -contains 'Operation' | Should -BeTrue
        }

        It 'Limits raw metrics with Last parameter' {
            $result = Get-LabPerformanceMetrics -Aggregated:$false -Last 3

            $result.Count | Should -Be 3
        }

        It 'Returns empty result when storage file not found' {
            Remove-Item $testStoragePath -Force

            $result = Get-LabPerformanceMetrics

            $result.TotalCount | Should -Be 0
        }

        It 'Handles corrupted JSON file gracefully' {
            'invalid json' | Set-Content -Path $testStoragePath

            $result = Get-LabPerformanceMetrics

            $result.TotalCount | Should -Be 0
        }

        It 'Filters by date range' {
            $cutoff = (Get-Date).AddMinutes(-5)
            $result = Get-LabPerformanceMetrics -After $cutoff

            $result.TotalCount | Should -Be 2
        }
    }
}
