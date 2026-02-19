Set-StrictMode -Version Latest

Describe 'Teardown policy' {
    BeforeAll {
        $coreResultPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $policyPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Policy/Resolve-LabTeardownPolicy.ps1'
        $actionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Actions/Invoke-LabTeardownAction.ps1'

        foreach ($requiredPath in @($coreResultPath, $policyPath, $actionPath)) {
            if (-not (Test-Path -Path $requiredPath)) {
                throw "Required test dependency is missing: $requiredPath"
            }
        }

        . $coreResultPath
        . $policyPath
        . $actionPath
    }

    It 'blocks full teardown without explicit approval' {
        $result = Invoke-LabTeardownAction -Mode full

        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'PolicyBlocked'
        $result.ErrorCode | Should -Be 'CONFIRMATION_REQUIRED'
    }

    It 'allows full teardown when force approval is explicit' {
        $result = Invoke-LabTeardownAction -Mode full -Force

        $result.PolicyOutcome | Should -Be 'Approved'
        $result.Succeeded | Should -BeTrue
        $result.FailureCategory | Should -Be $null
        $result.ErrorCode | Should -Be $null
    }

    It 'allows quick teardown without requiring force approval' {
        $result = Invoke-LabTeardownAction -Mode quick

        $result.PolicyOutcome | Should -Be 'Approved'
        $result.Succeeded | Should -BeTrue
        $result.FailureCategory | Should -Be $null
        $result.ErrorCode | Should -Be $null
    }

    It 'fails closed when policy evaluation throws unexpectedly' {
        Mock Resolve-LabTeardownPolicy {
            throw 'policy backend timeout'
        }

        { Invoke-LabTeardownAction -Mode quick } | Should -Not -Throw

        $result = Invoke-LabTeardownAction -Mode quick

        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'PolicyBlocked'
        $result.ErrorCode | Should -Be 'POLICY_EVALUATION_FAILED'
        $result.RecoveryHint | Should -Match 'policy backend timeout'
    }
}
