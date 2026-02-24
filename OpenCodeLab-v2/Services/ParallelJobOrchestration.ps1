function Invoke-ParallelLabJobs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,

        [Parameter(Mandatory)]
        [scriptblock]$WorkerScript,

        [Parameter(Mandatory)]
        [scriptblock]$NameScript,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds = 120
    )

    if ($Items.Count -eq 0) {
        return @()
    }

    $workerText = $WorkerScript.ToString()
    $jobs = @()

    foreach ($item in $Items) {
        $jobName = & $NameScript $item
        $jobs += Start-Job -Name $jobName -ScriptBlock {
            param($inputItem, $scriptText)

            try {
                $worker = [scriptblock]::Create($scriptText)
                & $worker $inputItem
            }
            catch {
                [pscustomobject]@{
                    Succeeded    = $false
                    ErrorMessage = $_.Exception.Message
                }
            }
        } -ArgumentList $item, $workerText
    }

    $startedAt = Get-Date
    $null = $jobs | Wait-Job -Timeout $TimeoutSeconds
    $durationMs = [int]((Get-Date) - $startedAt).TotalMilliseconds

    $results = @()

    foreach ($job in $jobs) {
        $output = @()
        $failureCategory = $null
        $errorMessage = ''
        $succeeded = $false
        $timedOut = $false

        if ($job.State -eq 'Running') {
            $timedOut = $true
            $failureCategory = 'Timeout'
            $errorMessage = "Job '$($job.Name)' exceeded timeout of $TimeoutSeconds second(s)."
            Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
        }
        elseif ($job.State -ne 'Completed') {
            $failureCategory = 'JobStateFailed'
            $errorMessage = "Job '$($job.Name)' ended in unexpected state '$($job.State)'."
        }

        if (-not $timedOut -and $job.State -eq 'Completed') {
            $output = @(Receive-Job -Id $job.Id -ErrorAction SilentlyContinue)

            if ($output.Count -eq 0) {
                $failureCategory = 'NoResult'
                $errorMessage = "Job '$($job.Name)' completed without output."
            }
            else {
                $last = $output[-1]
                $hasSucceeded = $last.PSObject.Properties.Name -contains 'Succeeded'
                if (-not $hasSucceeded) {
                    $failureCategory = 'NoResult'
                    $errorMessage = "Job '$($job.Name)' returned an invalid result contract."
                }
                elseif ([bool]$last.Succeeded) {
                    $succeeded = $true
                }
                else {
                    $failureCategory = 'ExecutionError'
                    if ($last.PSObject.Properties.Name -contains 'ErrorMessage' -and -not [string]::IsNullOrWhiteSpace([string]$last.ErrorMessage)) {
                        $errorMessage = [string]$last.ErrorMessage
                    }
                    else {
                        $errorMessage = "Job '$($job.Name)' reported failure."
                    }
                }
            }
        }

        $results += [pscustomobject]@{
            Name            = $job.Name
            Succeeded       = $succeeded
            State           = $job.State
            TimedOut        = $timedOut
            FailureCategory = $failureCategory
            ErrorMessage    = $errorMessage
            Output          = $output
            DurationMs      = $durationMs
        }

        Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
    }

    return $results
}
