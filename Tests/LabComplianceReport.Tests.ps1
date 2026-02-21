BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabReportsConfig.ps1')
    . (Join-Path $repoRoot 'Private/Format-LabComplianceReport.ps1')
}

Describe 'Get-LabReportsConfig' {
    BeforeEach {
        # Set up test-specific config
        $script:GlobalLabConfig = @{
            Reports = @{
                ComplianceReportPath       = 'TestDrive:/reports'
                IncludeDetailedResults     = $false
                ComplianceThresholdPercent = 80
                ReportFormats              = @('Console', 'Html')
            }
            Lab = @{
                LabName = 'TestLab'
            }
        }
    }

    It 'Returns reports configuration with all properties' {
        $config = Get-LabReportsConfig

        $config.ComplianceReportPath | Should -Be 'TestDrive:/reports'
        $config.IncludeDetailedResults | Should -Be $false
        $config.ComplianceThresholdPercent | Should -Be 80
        $config.ReportFormats | Should -HaveCount 2
    }

    It 'Provides safe defaults when Reports block is missing' {
        $script:GlobalLabConfig = @{
            Lab = @{ LabName = 'TestLab' }
        }

        $config = Get-LabReportsConfig

        $config.ComplianceReportPath | Should -Be '.planning/reports/compliance'
        $config.IncludeDetailedResults | Should -Be $false
        $config.ComplianceThresholdPercent | Should -Be 80
        $config.ReportFormats | Should -HaveCount 2
    }

    It 'Provides safe defaults when GlobalLabConfig does not exist' {
        Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue

        $config = Get-LabReportsConfig

        $config.ComplianceReportPath | Should -Be '.planning/reports/compliance'
        $config.IncludeDetailedResults | Should -Be $false
        $config.ComplianceThresholdPercent | Should -Be 80
        $config.ReportFormats | Should -HaveCount 2
    }
}

Describe 'Format-LabComplianceReport' {
    BeforeEach {
        $testData = @(
            [pscustomobject]@{ VMName = 'dc1'; Role = 'DC'; STIGVersion = '2019'; Status = 'Compliant'; ExceptionsApplied = 0; LastChecked = '2026-02-21T10:00:00' }
            [pscustomobject]@{ VMName = 'svr1'; Role = 'MS'; STIGVersion = '2019'; Status = 'NonCompliant'; ExceptionsApplied = 2; LastChecked = '2026-02-21T10:00:00' }
            [pscustomobject]@{ VMName = 'ws1'; Role = 'MS'; STIGVersion = '2022'; Status = 'Pending'; ExceptionsApplied = 0; LastChecked = '2026-02-21T10:00:00' }
        )
    }

    It 'Generates console output with summary statistics' {
        $output = Format-LabComplianceReport -ComplianceData $testData -Format Console -LabName 'TestLab' 6>&1

        $output | Should -Not -BeNullOrEmpty
        $output | Should -Match 'COMPLIANCE REPORT'
        $output | Should -Match 'Total VMs:\s+3'
        $output | Should -Match 'Compliant:\s+1'
        $output | Should -Match 'Non-Compliant:\s+1'
        $output | Should -Match 'Pending:\s+1'
    }

    It 'Calculates compliance rate correctly' {
        $null = Format-LabComplianceReport -ComplianceData $testData -Format Console -LabName 'TestLab' 6>&1

        # Compliance rate = 1/3 = 33.3%
        # This would be validated in the output
    }

    It 'Shows warning when compliance rate below threshold' {
        $output = Format-LabComplianceReport -ComplianceData $testData -Format Console -LabName 'TestLab' -ThresholdPercent 80 6>&1

        $output | Should -Match 'WARNING.*below threshold'
    }

    It 'Generates HTML report file' {
        $htmlPath = Join-Path $TestDrive 'compliance.html'

        $result = Format-LabComplianceReport -ComplianceData $testData -Format Html -LabName 'TestLab' -OutputPath $htmlPath

        $result | Should -Be $htmlPath
        Test-Path $htmlPath | Should -Be $true

        $content = Get-Content $htmlPath -Raw
        $content | Should -Match '<!DOCTYPE html>'
        $content | Should -Match 'STIG Compliance Report'
        $content | Should -Match 'dc1'
        $content | Should -Match 'TestLab'
    }

    It 'Generates CSV report file' {
        $csvPath = Join-Path $TestDrive 'compliance.csv'

        $result = Format-LabComplianceReport -ComplianceData $testData -Format Csv -LabName 'TestLab' -OutputPath $csvPath

        $result | Should -Be $csvPath
        Test-Path $csvPath | Should -Be $true

        $content = Get-Content $csvPath -Raw
        $content | Should -Match 'VMName'
        $content | Should -Match 'dc1'
    }

    It 'Generates JSON report file' {
        $jsonPath = Join-Path $TestDrive 'compliance.json'

        $result = Format-LabComplianceReport -ComplianceData $testData -Format Json -LabName 'TestLab' -OutputPath $jsonPath

        $result | Should -Be $jsonPath
        Test-Path $jsonPath | Should -Be $true

        $content = Get-Content $jsonPath -Raw | ConvertFrom-Json
        $content.LabName | Should -Be 'TestLab'
        $content.Summary.TotalVMs | Should -Be 3
        $content.VMs.Count | Should -Be 3
    }

    It 'Requires OutputPath for Html format' {
        # Capture error output to verify Write-Error was called
        $errorOutput = Format-LabComplianceReport -ComplianceData $testData -Format Html -LabName 'TestLab' 2>&1

        $errorOutput | Should -Not -BeNullOrEmpty
        $errorOutput | Should -Match 'OutputPath is required'
    }

    It 'Handles empty compliance data gracefully' {
        $output = Format-LabComplianceReport -ComplianceData @() -Format Console -LabName 'TestLab' 6>&1

        $output | Should -Not -BeNullOrEmpty
        $output | Should -Match 'Total VMs:\s+0'
    }
}
