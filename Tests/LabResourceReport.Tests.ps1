BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabResourceTrendCore.ps1')
    . (Join-Path $repoRoot 'Private/Format-LabResourceReport.ps1')

    $GlobalLabConfig = @{
        Lab = @{
            LabName = 'TestLab'
        }
    }
}

Describe 'Get-LabResourceTrendCore' {
    It 'Aggregates VM metrics by time period' {
        $testMetrics = @(
            [pscustomobject]@{ VMName = 'vm1'; CPUPercent = 50; MemoryGB = 4; DiskGB = 30; CollectedAt = '2026-02-21T10:00:00' }
            [pscustomobject]@{ VMName = 'vm2'; CPUPercent = 70; MemoryGB = 8; DiskGB = 50; CollectedAt = '2026-02-21T10:00:00' }
        )

        $result = Get-LabResourceTrendCore -VMMetrics $testMetrics -Period Day

        $result | Should -HaveCount 1
        $result[0].AvgCPU | Should -Be 60.0
        $result[0].AvgMemoryGB | Should -Be 6.0
        $result[0].AvgDiskGB | Should -Be 40.0
        $result[0].VMCount | Should -Be 2
    }

    It 'Calculates peak values correctly' {
        $testMetrics = @(
            [pscustomobject]@{ VMName = 'vm1'; CPUPercent = 30; MemoryGB = 4; DiskGB = 20; CollectedAt = '2026-02-21T10:00:00' }
            [pscustomobject]@{ VMName = 'vm2'; CPUPercent = 90; MemoryGB = 16; DiskGB = 80; CollectedAt = '2026-02-21T10:00:00' }
        )

        $result = Get-LabResourceTrendCore -VMMetrics $testMetrics -Period Day

        $result[0].PeakCPU | Should -Be 90.0
        $result[0].PeakMemoryGB | Should -Be 16.0
        $result[0].PeakDiskGB | Should -Be 80.0
    }

    It 'Groups by different time periods' {
        $testMetrics = @(
            [pscustomobject]@{ VMName = 'vm1'; CPUPercent = 50; MemoryGB = 4; DiskGB = 30; CollectedAt = '2026-02-21T10:00:00' }
            [pscustomobject]@{ VMName = 'vm2'; CPUPercent = 50; MemoryGB = 4; DiskGB = 30; CollectedAt = '2026-02-22T10:00:00' }
        )

        $dayResult = Get-LabResourceTrendCore -VMMetrics $testMetrics -Period Day
        $dayResult | Should -HaveCount 2

        $weekResult = Get-LabResourceTrendCore -VMMetrics $testMetrics -Period Week
        # Both metrics fall in the same week
        $weekResult | Should -HaveCount 1
    }

    It 'Returns empty array when no metrics provided' {
        $result = Get-LabResourceTrendCore -VMMetrics $null -Period Day

        # Result should be empty (either null or empty array)
        if ($null -ne $result) {
            $result.Count | Should -Be 0
        } else {
            # null is acceptable for empty input
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Format-LabResourceReport' {
    BeforeEach {
        $testData = @(
            [pscustomobject]@{ VMName = 'dc1'; CPUPercent = 25; MemoryGB = 2; DiskGB = 40 }
            [pscustomobject]@{ VMName = 'svr1'; CPUPercent = 85; MemoryGB = 12; DiskGB = 90 }
            [pscustomobject]@{ VMName = 'ws1'; CPUPercent = 45; MemoryGB = 4; DiskGB = 55 }
        )
    }

    It 'Generates console output with summary statistics' {
        $output = Format-LabResourceReport -ResourceData $testData -Format Console -LabName 'TestLab' 6>&1

        $output | Should -Not -BeNullOrEmpty
        $output | Should -Match 'RESOURCE UTILIZATION REPORT'
        $output | Should -Match 'Avg CPU:'
        $output | Should -Match 'Avg Memory:'
        $output | Should -Match 'Avg Disk:'
    }

    It 'Identifies bottlenecks correctly' {
        $thresholds = @{
            CPUWarning    = 70
            MemoryWarning = 80
            DiskWarning   = 80
        }

        $output = Format-LabResourceReport -ResourceData $testData -Format Console -LabName 'TestLab' -Thresholds $thresholds 6>&1

        $output | Should -Match 'BOTTLENECKS DETECTED'
        $output | Should -Match 'svr1'
    }

    It 'Generates HTML report file' {
        $htmlPath = Join-Path $TestDrive 'resources.html'

        $result = Format-LabResourceReport -ResourceData $testData -Format Html -LabName 'TestLab' -OutputPath $htmlPath

        $result | Should -Be $htmlPath
        Test-Path $htmlPath | Should -Be $true

        $content = Get-Content $htmlPath -Raw
        $content | Should -Match '<!DOCTYPE html>'
        $content | Should -Match 'Resource Utilization Report'
        $content | Should -Match 'dc1'
    }

    It 'Generates CSV report file' {
        $csvPath = Join-Path $TestDrive 'resources.csv'

        $result = Format-LabResourceReport -ResourceData $testData -Format Csv -LabName 'TestLab' -OutputPath $csvPath

        $result | Should -Be $csvPath
        Test-Path $csvPath | Should -Be $true

        $content = Get-Content $csvPath -Raw
        $content | Should -Match 'VMName'
        $content | Should -Match 'CPUPercent'
    }

    It 'Generates JSON report file with summary' {
        $jsonPath = Join-Path $TestDrive 'resources.json'

        $result = Format-LabResourceReport -ResourceData $testData -Format Json -LabName 'TestLab' -OutputPath $jsonPath

        $result | Should -Be $jsonPath
        Test-Path $jsonPath | Should -Be $true

        $content = Get-Content $jsonPath -Raw | ConvertFrom-Json
        $content.LabName | Should -Be 'TestLab'
        $content.Summary.TotalVMs | Should -Be 3
        $content.VMs.Count | Should -Be 3
    }

    It 'Handles VMs with different metric property names' {
        $mixedData = @(
            [pscustomobject]@{ VMName = 'dc1'; CPU = 25; Memory = 2048; DiskUsagePercent = 40 }
            [pscustomobject]@{ VMName = 'svr1'; CPUPercent = 85; MemoryGB = 12; DiskGB = 90 }
        )

        $output = Format-LabResourceReport -ResourceData $mixedData -Format Console -LabName 'TestLab' 6>&1

        $output | Should -Not -BeNullOrEmpty
        $output | Should -Match 'Total VMs:\s+2'
    }

    It 'Requires OutputPath for Html format' {
        # Capture error output to verify Write-Error was called
        $errorOutput = Format-LabResourceReport -ResourceData $testData -Format Html -LabName 'TestLab' 2>&1

        $errorOutput | Should -Not -BeNullOrEmpty
        $errorOutput | Should -Match 'OutputPath is required'
    }

    It 'Handles empty resource data gracefully' {
        $output = Format-LabResourceReport -ResourceData @() -Format Console -LabName 'TestLab' 6>&1

        $output | Should -Not -BeNullOrEmpty
        $output | Should -Match 'Total VMs:\s+0'
    }
}
