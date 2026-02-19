Set-StrictMode -Version Latest

Describe 'Deploy action' {
    BeforeAll {
        $coreResultPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $statePath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/State/Invoke-LabDeployStateMachine.ps1'
        $actionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Actions/Invoke-LabDeployAction.ps1'

        foreach ($requiredPath in @($coreResultPath, $statePath, $actionPath)) {
            if (-not (Test-Path -Path $requiredPath)) {
                throw "Required test dependency is missing: $requiredPath"
            }
        }

        . $coreResultPath
        . $statePath
        . $actionPath
    }

    It 'supports full mode and calls baseline full state machine mode' {
        Mock Invoke-LabDeployStateMachine {}

        $result = Invoke-LabDeployAction -Mode 'full'

        $result.Succeeded | Should -BeTrue
        $result.RequestedMode | Should -Be 'full'
        $result.EffectiveMode | Should -Be 'full'

        Assert-MockCalled Invoke-LabDeployStateMachine -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'full' }
    }

    It 'supports quick mode and still calls baseline full state machine mode' {
        Mock Invoke-LabDeployStateMachine {}

        $result = Invoke-LabDeployAction -Mode 'quick'

        $result.Succeeded | Should -BeTrue
        $result.RequestedMode | Should -Be 'quick'
        $result.EffectiveMode | Should -Be 'full'

        Assert-MockCalled Invoke-LabDeployStateMachine -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'full' }
    }

    It 'returns OperationFailed classification when the state machine throws' {
        Mock Invoke-LabDeployStateMachine {
            throw 'adapter failed'
        }

        { Invoke-LabDeployAction -Mode full } | Should -Not -Throw

        $result = Invoke-LabDeployAction -Mode full

        $result.Succeeded | Should -BeFalse
        $result.EffectiveMode | Should -Be 'full'
        $result.FailureCategory | Should -Be 'OperationFailed'
        $result.ErrorCode | Should -Be 'DEPLOY_STEP_FAILED'
        $result.RecoveryHint | Should -Match 'adapter failed'
    }

    It 'keeps effective mode full when quick mode encounters an exception' {
        Mock Invoke-LabDeployStateMachine {
            throw 'quick mode failure'
        }

        $result = Invoke-LabDeployAction -Mode quick

        $result.Succeeded | Should -BeFalse
        $result.RequestedMode | Should -Be 'quick'
        $result.EffectiveMode | Should -Be 'full'
        $result.FailureCategory | Should -Be 'OperationFailed'
        $result.ErrorCode | Should -Be 'DEPLOY_STEP_FAILED'
        $result.RecoveryHint | Should -Match 'quick mode failure'
    }

    It 'propagates non-throw failure contract from the state machine' {
        Mock Invoke-LabDeployStateMachine {
            [pscustomobject]@{
                Succeeded       = $false
                FailureCategory = 'PolicyBlocked'
                ErrorCode       = 'DEPLOY_DENIED'
                RecoveryHint    = 'Review policy and retry deployment.'
            }
        }

        $result = Invoke-LabDeployAction -Mode full

        $result.Succeeded | Should -BeFalse
        $result.EffectiveMode | Should -Be 'full'
        $result.FailureCategory | Should -Be 'PolicyBlocked'
        $result.ErrorCode | Should -Be 'DEPLOY_DENIED'
        $result.RecoveryHint | Should -Be 'Review policy and retry deployment.'
    }
}
