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

        $result = Invoke-LabDeployAction -Mode full

        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'OperationFailed'
        $result.ErrorCode | Should -Be 'DEPLOY_STEP_FAILED'
    }
}
