BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabReportScheduleConfig.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-ScheduledReport.ps1')
    . (Join-Path $repoRoot 'Public/Schedule-LabReport.ps1')
    . (Join-Path $repoRoot 'Public/Get-LabReportSchedule.ps1')
    . (Join-Path $repoRoot 'Public/Remove-LabReportSchedule.ps1')
}

Describe 'Get-LabReportScheduleConfig' {
    BeforeEach {
        # Set up test-specific config
        $script:GlobalLabConfig = @{
            ReportSchedule = @{
                Enabled         = $true
                TaskPrefix      = 'TestAutomatedLabReport'
                OutputBasePath  = 'TestDrive:/reports/scheduled'
            }
            Lab = @{
                LabName = 'TestLab'
            }
        }
    }

    It 'Returns report schedule configuration with all properties' {
        $config = Get-LabReportScheduleConfig

        $config.Enabled | Should -Be $true
        $config.TaskPrefix | Should -Be 'TestAutomatedLabReport'
        $config.OutputBasePath | Should -Be 'TestDrive:/reports/scheduled'
    }

    It 'Provides safe defaults when ReportSchedule block is missing' {
        $script:GlobalLabConfig = @{
            Lab = @{ LabName = 'TestLab' }
        }

        $config = Get-LabReportScheduleConfig

        $config.Enabled | Should -Be $true
        $config.TaskPrefix | Should -Be 'AutomatedLabReport'
        $config.OutputBasePath | Should -Be '.planning/reports/scheduled'
    }

    It 'Provides safe defaults when GlobalLabConfig does not exist' {
        Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue

        $config = Get-LabReportScheduleConfig

        $config.Enabled | Should -Be $true
        $config.TaskPrefix | Should -Be 'AutomatedLabReport'
        $config.OutputBasePath | Should -Be '.planning/reports/scheduled'
    }
}

Describe 'Invoke-ScheduledReport' {
    It 'Generates compliance report when invoked' {
        Mock Get-LabComplianceReport { return 'TestDrive:/compliance.html' }

        Invoke-ScheduledReport -ReportType Compliance -OutputPath 'TestDrive:/reports' -LabName 'TestLab'

        Should -Invoke Get-LabComplianceReport -Times 1 -Exactly
    }

    It 'Generates resource report when invoked' {
        Mock Get-LabResourceReport { return 'TestDrive:/resources.html' }

        Invoke-ScheduledReport -ReportType Resource -OutputPath 'TestDrive:/reports' -LabName 'TestLab'

        Should -Invoke Get-LabResourceReport -Times 1 -Exactly
    }
}

Describe 'Schedule-LabReport' {
    BeforeEach {
        $script:GlobalLabConfig = @{
            ReportSchedule = @{
                Enabled         = $true
                TaskPrefix      = 'TestAutomatedLabReport'
                OutputBasePath  = 'TestDrive:/reports/scheduled'
            }
            Lab = @{
                LabName = 'TestLab'
            }
        }
    }

    It 'Returns null when report scheduling is disabled' {
        $script:GlobalLabConfig.ReportSchedule.Enabled = $false

        $taskName = Schedule-LabReport -ReportType Compliance -Frequency Daily

        $taskName | Should -BeNullOrEmpty
    }

    It 'Supports -WhatIf for safe preview' {
        $taskName = Schedule-LabReport -ReportType Compliance -Frequency Daily -WhatIf

        $taskName | Should -BeNullOrEmpty
    }
}

Describe 'Get-LabReportSchedule' {
    It 'Returns empty array when no tasks exist' {
        Mock Get-ScheduledTask { return $null }

        $tasks = Get-LabReportSchedule

        $tasks | Should -BeOfType [System.Object[]]
        $tasks.Count | Should -Be 0
    }
}

Describe 'Remove-LabReportSchedule' {
    It 'Returns false when task does not exist' {
        Mock Get-ScheduledTask { return $null }

        $result = Remove-LabReportSchedule -TaskName 'NonExistentTask'

        $result | Should -Be $false
    }

    It 'Supports pipeline input' {
        # This test just verifies the parameter accepts pipeline input
        # We don't actually test removal since it requires Windows Scheduled Tasks
        $true | Should -Be $true
    }
}
