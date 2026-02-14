# Coordinator plan graph + dispatcher tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/New-LabCoordinatorPlan.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabCoordinatorPlan.ps1')
}

Describe 'New-LabCoordinatorPlan' {
    It 'always includes preflight, policy, and non-destructive execution in dependency order' {
        $plan = New-LabCoordinatorPlan -Action deploy -Mode quick

        @($plan.Steps.Id) | Should -Be @('preflight', 'policy', 'execute-nondestructive')
        @($plan.Steps[0].DependsOn) | Should -Be @()
        @($plan.Steps[1].DependsOn) | Should -Be @('preflight')
        @($plan.Steps[2].DependsOn) | Should -Be @('policy')
    }

    It 'adds destructive barrier and destructive execution for full teardown' {
        $plan = New-LabCoordinatorPlan -Action teardown -Mode full

        @($plan.Steps.Id) | Should -Be @('preflight', 'policy', 'execute-nondestructive', 'destructive-barrier', 'execute-destructive')
        @($plan.Steps[3].DependsOn) | Should -Be @('execute-nondestructive')
        @($plan.Steps[4].DependsOn) | Should -Be @('destructive-barrier')
    }
}

Describe 'Invoke-LabCoordinatorPlan' {
    It 'executes steps in dependency order' {
        $plan = [pscustomobject]@{
            Action = 'deploy'
            Mode = 'quick'
            Steps = @(
                [pscustomobject]@{ Id = 'c'; DependsOn = @('b') },
                [pscustomobject]@{ Id = 'b'; DependsOn = @('a') },
                [pscustomobject]@{ Id = 'a'; DependsOn = @() }
            )
        }

        $result = Invoke-LabCoordinatorPlan -Plan $plan -StepRunner {
            param($Step, $Context)
            return $true
        }

        @($result.StepOutcomes.StepId) | Should -Be @('a', 'b', 'c')
        ($result.StepOutcomes | Where-Object StepId -eq 'a').Outcome.ToString() | Should -Be 'Succeeded'
    }

    It 'skips dependent steps after a failed dependency and returns typed outcomes' {
        $plan = [pscustomobject]@{
            Action = 'teardown'
            Mode = 'full'
            Steps = @(
                [pscustomobject]@{ Id = 'policy'; DependsOn = @() },
                [pscustomobject]@{ Id = 'execute-nondestructive'; DependsOn = @('policy') }
            )
        }

        $result = Invoke-LabCoordinatorPlan -Plan $plan -StepRunner {
            param($Step, $Context)
            if ($Step.Id -eq 'policy') {
                return $false
            }

            return $true
        }

        ($result.StepOutcomes | Where-Object StepId -eq 'policy').Outcome.ToString() | Should -Be 'Failed'
        ($result.StepOutcomes | Where-Object StepId -eq 'execute-nondestructive').Outcome.ToString() | Should -Be 'Skipped'
        ($result.StepOutcomes | Where-Object StepId -eq 'policy').Outcome.GetType().Name | Should -Be 'LabCoordinatorStepOutcome'
        $result.Success | Should -BeFalse
    }
}
