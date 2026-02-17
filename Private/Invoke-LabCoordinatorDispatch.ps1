function Invoke-LabCoordinatorDispatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('deploy', 'teardown')]
        [string]$Action,

        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$EffectiveMode,

        [Parameter(Mandatory)]
        [ValidateSet('off', 'canary', 'enforced')]
        [string]$DispatchMode,

        [Parameter(Mandatory)]
        [string[]]$TargetHosts,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxRetryCount = 0,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetryDelayMilliseconds = 0,

        [Parameter()]
        [scriptblock]$HostStepRunner = {
            param($HostName, $Action, $EffectiveMode, $Attempt)
            return $true
        }
    )

    $executionStartedAt = Get-Date

    $resolvedTargets = @($TargetHosts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($resolvedTargets.Count -eq 0) {
        throw "TargetHosts must contain at least one non-empty host name."
    }

    $hostOutcomes = New-Object System.Collections.ArrayList

    if ($DispatchMode -eq 'off') {
        foreach ($hostName in @($resolvedTargets)) {
            [void]$hostOutcomes.Add([pscustomobject]@{
                HostName = [string]$hostName
                DispatchStatus = 'not_dispatched'
                AttemptCount = 0
                LastFailureClass = $null
                LastFailureMessage = $null
            })
        }

        return [pscustomobject]@{
            DispatchMode = $DispatchMode
            ExecutionOutcome = 'not_dispatched'
            ExecutionStartedAt = $executionStartedAt
            ExecutionCompletedAt = Get-Date
            HostOutcomes = @($hostOutcomes)
        }
    }

    $stopOnFirstFailure = ($Action -eq 'teardown' -and $EffectiveMode -eq 'full')
    $abortRemaining = $false

    for ($hostIndex = 0; $hostIndex -lt @($resolvedTargets).Count; $hostIndex++) {
        $hostName = [string]$resolvedTargets[$hostIndex]
        $isCanarySkipped = ($DispatchMode -eq 'canary' -and $hostIndex -gt 0)

        if ($isCanarySkipped) {
            [void]$hostOutcomes.Add([pscustomobject]@{
                HostName = $hostName
                DispatchStatus = 'not_dispatched'
                AttemptCount = 0
                LastFailureClass = $null
                LastFailureMessage = $null
            })
            continue
        }

        if ($abortRemaining) {
            [void]$hostOutcomes.Add([pscustomobject]@{
                HostName = $hostName
                DispatchStatus = 'skipped'
                AttemptCount = 0
                LastFailureClass = $null
                LastFailureMessage = $null
            })
            continue
        }

        $attemptCount = 0
        $lastFailureClass = $null
        $lastFailureMessage = $null
        $dispatchStatus = 'failed'

        while ($attemptCount -lt (1 + $MaxRetryCount)) {
            $attemptCount++

            try {
                $runnerResult = & $HostStepRunner $hostName $Action $EffectiveMode $attemptCount
                $runnerSucceeded = $true

                if ($runnerResult -is [bool]) {
                    $runnerSucceeded = $runnerResult
                }
                elseif ($null -eq $runnerResult) {
                    $runnerSucceeded = $true
                }
                else {
                    $runnerSucceeded = [bool]$runnerResult
                }

                if ($runnerSucceeded) {
                    $dispatchStatus = 'succeeded'
                    $lastFailureClass = $null
                    $lastFailureMessage = $null
                    break
                }

                $dispatchStatus = 'failed'
                $lastFailureClass = 'non_transient'
                $lastFailureMessage = 'Host step runner returned unsuccessful result.'
                break
            }
            catch {
                $dispatchStatus = 'failed'
                $lastFailureMessage = $_.Exception.Message
                if ([string]::IsNullOrWhiteSpace($lastFailureMessage)) {
                    $lastFailureMessage = [string]$_
                }

                $isTransientFailure = Test-LabTransientTransportFailure -Message $lastFailureMessage
                $lastFailureClass = if ($isTransientFailure) { 'transient' } else { 'non_transient' }

                if (-not $isTransientFailure) {
                    break
                }

                if ($attemptCount -ge (1 + $MaxRetryCount)) {
                    break
                }

                if ($RetryDelayMilliseconds -gt 0) {
                    Start-Sleep -Milliseconds $RetryDelayMilliseconds
                }
            }
        }

        [void]$hostOutcomes.Add([pscustomobject]@{
            HostName = $hostName
            DispatchStatus = $dispatchStatus
            AttemptCount = $attemptCount
            LastFailureClass = $lastFailureClass
            LastFailureMessage = $lastFailureMessage
        })

        if ($dispatchStatus -eq 'failed' -and $stopOnFirstFailure) {
            $abortRemaining = $true
        }
    }

    $allHostOutcomes = @($hostOutcomes)
    $failedCount = @($allHostOutcomes | Where-Object { $_.DispatchStatus -eq 'failed' }).Count
    $succeededCount = @($allHostOutcomes | Where-Object { $_.DispatchStatus -eq 'succeeded' }).Count

    $executionOutcome = 'not_dispatched'
    if ($failedCount -gt 0 -and $succeededCount -gt 0) {
        $executionOutcome = 'partial'
    }
    elseif ($failedCount -gt 0) {
        $executionOutcome = 'failed'
    }
    elseif ($succeededCount -gt 0) {
        $executionOutcome = 'succeeded'
    }

    return [pscustomobject]@{
        DispatchMode = $DispatchMode
        ExecutionOutcome = $executionOutcome
        ExecutionStartedAt = $executionStartedAt
        ExecutionCompletedAt = Get-Date
        HostOutcomes = $allHostOutcomes
    }
}
