Describe 'Write-LabOperationSummary' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module "$moduleRoot\SimpleLab\SimpleLab.psd1" -Force

        . "$moduleRoot\Private\Write-LabOperationSummary.ps1"
    }

    Context 'Bulk operation summary formatting' {
        It 'Formats summary for successful bulk operation' {
            $result = [pscustomobject]@{
                OverallStatus = 'OK'
                Operation = 'Start'
                OperationCount = 3
                Duration = [TimeSpan]::Parse('00:00:05.234')
                Success = @('vm1', 'vm2', 'vm3')
                Failed = @()
                Skipped = @()
                Parallel = $false
            }

            $summary = Write-LabOperationSummary -Operation 'Start' -Result $result

            $summary.FormattedSummary | Should -Match 'Operation Summary: Start'
            $summary.FormattedSummary | Should -Match 'Overall Status: OK'
            $summary.FormattedSummary | Should -Match 'Success: 3 VM\(s\)'
            $summary.FormattedSummary | Should -Match 'vm1.*vm2.*vm3'
        }

        It 'Formats summary with failed operations' {
            $result = [pscustomobject]@{
                OverallStatus = 'Partial'
                Operation = 'Stop'
                OperationCount = 3
                Duration = [TimeSpan]::Parse('00:00:03.123')
                Success = @('vm1')
                Failed = @([pscustomobject]@{ VMName = 'vm2'; Error = 'VM not responding' })
                Skipped = @('vm3 (already off)')
                Parallel = $false
            }

            $summary = Write-LabOperationSummary -Operation 'Stop' -Result $result

            $summary.FormattedSummary | Should -Match 'Overall Status: Partial'
            $summary.FormattedSummary | Should -Match 'Success: 1 VM\(s\)'
            $summary.FormattedSummary | Should -Match 'Failed: 1 VM\(s\)'
            $summary.FormattedSummary | Should -Match 'vm2: VM not responding'
            $summary.FormattedSummary | Should -Match 'Skipped: 1 VM\(s\)'
        }

        It 'Formats duration correctly' {
            $result = [pscustomobject]@{
                OverallStatus = 'OK'
                Operation = 'Start'
                OperationCount = 1
                Duration = [TimeSpan]::Parse('00:01:23.456')
                Success = @('vm1')
                Failed = @()
                Skipped = @()
                Parallel = $false
            }

            $summary = Write-LabOperationSummary -Operation 'Start' -Result $result

            $summary.FormattedSummary | Should -Match 'Duration: 01\:23\.456'
        }
    }

    Context 'Workflow summary formatting' {
        It 'Formats summary for workflow execution' {
            $result = [pscustomobject]@{
                WorkflowName = 'TestWorkflow'
                OverallStatus = 'Completed'
                TotalSteps = 2
                CompletedSteps = 2
                FailedSteps = 0
                Duration = [TimeSpan]::Parse('00:00:10.500')
                Results = @(
                    [pscustomobject]@{
                        StepNumber = 1
                        Operation = 'Start'
                        Status = 'OK'
                        VMName = @('dc1')
                        SuccessCount = 1
                        FailedCount = 0
                        SkippedCount = 0
                        Error = $null
                    },
                    [pscustomobject]@{
                        StepNumber = 2
                        Operation = 'Start'
                        Status = 'OK'
                        VMName = @('svr1')
                        SuccessCount = 1
                        FailedCount = 0
                        SkippedCount = 0
                        Error = $null
                    }
                )
            }

            $summary = Write-LabOperationSummary -Operation 'TestWorkflow' -Result $result -WorkflowMode

            $summary.FormattedSummary | Should -Match 'Workflow: TestWorkflow'
            $summary.FormattedSummary | Should -Match 'Steps Completed: 2 / 2'
            $summary.FormattedSummary | Should -Match 'Step 1: .* Start'
            $summary.FormattedSummary | Should -Match 'Step 2: .* Start'
        }

        It 'Formats summary with failed workflow steps' {
            $result = [pscustomobject]@{
                WorkflowName = 'FailingWorkflow'
                OverallStatus = 'Partial'
                TotalSteps = 2
                CompletedSteps = 2
                FailedSteps = 1
                Duration = [TimeSpan]::Parse('00:00:05.000')
                Results = @(
                    [pscustomobject]@{
                        StepNumber = 1
                        Operation = 'Start'
                        Status = 'OK'
                        VMName = @('dc1')
                    },
                    [pscustomobject]@{
                        StepNumber = 2
                        Operation = 'Start'
                        Status = 'Failed'
                        VMName = @('svr1')
                        Error = 'VM not found'
                    }
                )
            }

            $summary = Write-LabOperationSummary -Operation 'FailingWorkflow' -Result $result -WorkflowMode

            $summary.FormattedSummary | Should -Match 'Failed Steps: 1'
            $summary.FormattedSummary | Should -Match 'Step 2: .* Start'
            $summary.FormattedSummary | Should -Match 'Error: VM not found'
        }
    }

    Context 'Summary object properties' {
        It 'Returns summary object with all required properties' {
            $result = [pscustomobject]@{
                OverallStatus = 'OK'
                Operation = 'Start'
                OperationCount = 1
                Duration = [TimeSpan]::Parse('00:00:01.000')
                Success = @('vm1')
                Failed = @()
                Skipped = @()
                Parallel = $false
            }

            $summary = Write-LabOperationSummary -Operation 'Start' -Result $result

            $summary.Timestamp | Should -Not -BeNullOrEmpty
            $summary.Operation | Should -Be 'Start'
            $summary.OverallStatus | Should -Be 'OK'
            $summary.FormattedSummary | Should -Not -BeNullOrEmpty
        }
    }
}
