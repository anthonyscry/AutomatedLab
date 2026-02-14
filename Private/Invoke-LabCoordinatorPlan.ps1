if (-not ('LabCoordinatorStepOutcome' -as [type])) {
    Add-Type -TypeDefinition @"
public enum LabCoordinatorStepOutcome
{
    Succeeded = 0,
    Failed = 1,
    Skipped = 2
}
"@
}

function Invoke-LabCoordinatorPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Plan,

        [Parameter()]
        [scriptblock]$StepRunner = {
            param($Step, $Context)
            return $true
        }
    )

    $pendingById = @{}
    $sourceOrder = @{}
    $index = 0

    foreach ($step in @($Plan.Steps)) {
        $pendingById[[string]$step.Id] = $step
        $sourceOrder[[string]$step.Id] = $index
        $index++
    }

    $outcomes = New-Object System.Collections.ArrayList

    while ($pendingById.Count -gt 0) {
        $readySteps = @()
        foreach ($stepId in @($pendingById.Keys)) {
            $step = $pendingById[$stepId]
            $dependsOn = @($step.DependsOn)
            $unresolvedDependency = $false

            foreach ($dependencyId in $dependsOn) {
                if ($pendingById.ContainsKey([string]$dependencyId)) {
                    $unresolvedDependency = $true
                    break
                }
            }

            if (-not $unresolvedDependency) {
                $readySteps += $step
            }
        }

        if (@($readySteps).Count -eq 0) {
            throw 'Coordinator plan has unresolved dependency cycle.'
        }

        $readySteps = @($readySteps | Sort-Object { $sourceOrder[[string]$_.Id] })

        foreach ($step in $readySteps) {
            $dependsOn = @($step.DependsOn)
            $blockedByFailure = $false

            foreach ($dependencyId in $dependsOn) {
                $dependencyOutcome = $outcomes | Where-Object { $_.StepId -eq [string]$dependencyId } | Select-Object -First 1
                if ($null -eq $dependencyOutcome) {
                    continue
                }

                if ($dependencyOutcome.Outcome -ne [LabCoordinatorStepOutcome]::Succeeded) {
                    $blockedByFailure = $true
                    break
                }
            }

            if ($blockedByFailure) {
                [void]$outcomes.Add([pscustomobject]@{
                    StepId = [string]$step.Id
                    Outcome = [LabCoordinatorStepOutcome]::Skipped
                })
                $pendingById.Remove([string]$step.Id)
                continue
            }

            $runnerSucceeded = $true
            try {
                $runnerResult = & $StepRunner $step $Plan
                if ($runnerResult -is [bool]) {
                    $runnerSucceeded = $runnerResult
                }
                elseif ($null -eq $runnerResult) {
                    $runnerSucceeded = $true
                }
                else {
                    $runnerSucceeded = [bool]$runnerResult
                }
            }
            catch {
                $runnerSucceeded = $false
            }

            $outcome = if ($runnerSucceeded) { [LabCoordinatorStepOutcome]::Succeeded } else { [LabCoordinatorStepOutcome]::Failed }
            [void]$outcomes.Add([pscustomobject]@{
                StepId = [string]$step.Id
                Outcome = $outcome
            })

            $pendingById.Remove([string]$step.Id)
        }
    }

    $allSucceeded = @($outcomes).Count -gt 0 -and -not (@($outcomes | Where-Object { $_.Outcome -ne [LabCoordinatorStepOutcome]::Succeeded }).Count -gt 0)

    return [pscustomobject]@{
        Action = [string]$Plan.Action
        Mode = [string]$Plan.Mode
        Success = $allSucceeded
        StepOutcomes = @($outcomes)
    }
}
