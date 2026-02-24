BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:repoRoot 'Services' 'ParallelJobOrchestration.ps1')
}

Describe 'Invoke-ParallelLabJobs' {
    It 'classifies timed out jobs as Timeout failures' {
        Mock Start-Job {
            [pscustomobject]@{ Id = 1001; Name = 'internet-DC1'; State = 'Running' }
        }

        Mock Wait-Job { }
        Mock Receive-Job { @() }
        Mock Stop-Job { }
        Mock Remove-Job { }

        $worker = {
            param($item)
            [pscustomobject]@{
                VMName       = $item.VMName
                Succeeded    = $true
                ErrorMessage = ''
            }
        }

        $results = Invoke-ParallelLabJobs -Items @([pscustomobject]@{ VMName = 'DC1' }) -WorkerScript $worker -TimeoutSeconds 1 -NameScript {
            param($item)
            "internet-$($item.VMName)"
        }

        $results.Count | Should -Be 1
        $results[0].Succeeded | Should -BeFalse
        $results[0].TimedOut | Should -BeTrue
        $results[0].FailureCategory | Should -Be 'Timeout'
    }

    It 'classifies completed jobs with missing contract as NoResult failures' {
        Mock Start-Job {
            [pscustomobject]@{ Id = 1002; Name = 'internet-SVR1'; State = 'Completed' }
        }

        Mock Wait-Job { }
        Mock Receive-Job { @([pscustomobject]@{ VMName = 'SVR1' }) }
        Mock Stop-Job { }
        Mock Remove-Job { }

        $worker = {
            param($item)
            [pscustomobject]@{ VMName = $item.VMName }
        }

        $results = Invoke-ParallelLabJobs -Items @([pscustomobject]@{ VMName = 'SVR1' }) -WorkerScript $worker -TimeoutSeconds 1 -NameScript {
            param($item)
            "internet-$($item.VMName)"
        }

        $results[0].Succeeded | Should -BeFalse
        $results[0].FailureCategory | Should -Be 'NoResult'
    }

    It 'returns successful results when worker returns Succeeded true' {
        Mock Start-Job {
            [pscustomobject]@{ Id = 1003; Name = 'internet-WS1'; State = 'Completed' }
        }

        Mock Wait-Job { }
        Mock Receive-Job {
            @([pscustomobject]@{ VMName = 'WS1'; Succeeded = $true; ErrorMessage = '' })
        }
        Mock Stop-Job { }
        Mock Remove-Job { }

        $worker = {
            param($item)
            [pscustomobject]@{ VMName = $item.VMName; Succeeded = $true; ErrorMessage = '' }
        }

        $results = Invoke-ParallelLabJobs -Items @([pscustomobject]@{ VMName = 'WS1' }) -WorkerScript $worker -TimeoutSeconds 1 -NameScript {
            param($item)
            "internet-$($item.VMName)"
        }

        $results[0].Succeeded | Should -BeTrue
        $results[0].FailureCategory | Should -BeNullOrEmpty
    }
}
