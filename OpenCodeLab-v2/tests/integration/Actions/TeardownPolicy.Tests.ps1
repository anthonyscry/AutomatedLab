Set-StrictMode -Version Latest

Describe 'Teardown policy' {
    BeforeAll {
        $coreResultPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $enterLockPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/Enter-LabRunLock.ps1'
        $exitLockPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/Exit-LabRunLock.ps1'
        $policyPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Policy/Resolve-LabTeardownPolicy.ps1'
        $actionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Actions/Invoke-LabTeardownAction.ps1'

        foreach ($requiredPath in @($coreResultPath, $enterLockPath, $exitLockPath, $policyPath, $actionPath)) {
            if (-not (Test-Path -Path $requiredPath)) {
                throw "Required test dependency is missing: $requiredPath"
            }
        }

        . $coreResultPath
        . $enterLockPath
        . $exitLockPath
        . $policyPath
        . $actionPath
    }

    It 'blocks full teardown without explicit approval' {
        Mock Enter-LabRunLock { [pscustomobject]@{ Path = 'lock'; OwnerToken = 'token' } }
        Mock Exit-LabRunLock {}
        $result = Invoke-LabTeardownAction -Mode full

        $result.PolicyOutcome | Should -Be 'PolicyBlocked'
        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'PolicyBlocked'
        $result.ErrorCode | Should -Be 'CONFIRMATION_REQUIRED'
        Assert-MockCalled Enter-LabRunLock -Times 1 -Exactly -Scope It
        Assert-MockCalled Exit-LabRunLock -Times 1 -Exactly -Scope It
    }

    It 'allows full teardown when force approval is explicit' {
        Mock Enter-LabRunLock { [pscustomobject]@{ Path = 'lock'; OwnerToken = 'token' } }
        Mock Exit-LabRunLock {}
        $result = Invoke-LabTeardownAction -Mode full -Force

        $result.PolicyOutcome | Should -Be 'Approved'
        $result.Succeeded | Should -BeTrue
        $result.FailureCategory | Should -Be $null
        $result.ErrorCode | Should -Be $null
        Assert-MockCalled Enter-LabRunLock -Times 1 -Exactly -Scope It
        Assert-MockCalled Exit-LabRunLock -Times 1 -Exactly -Scope It
    }

    It 'allows quick teardown without requiring force approval' {
        Mock Enter-LabRunLock { [pscustomobject]@{ Path = 'lock'; OwnerToken = 'token' } }
        Mock Exit-LabRunLock {}
        $result = Invoke-LabTeardownAction -Mode quick

        $result.PolicyOutcome | Should -Be 'Approved'
        $result.Succeeded | Should -BeTrue
        $result.FailureCategory | Should -Be $null
        $result.ErrorCode | Should -Be $null
        Assert-MockCalled Enter-LabRunLock -Times 1 -Exactly -Scope It
        Assert-MockCalled Exit-LabRunLock -Times 1 -Exactly -Scope It
    }

    It 'fails closed when policy evaluation throws unexpectedly' {
        Mock Enter-LabRunLock { [pscustomobject]@{ Path = 'lock'; OwnerToken = 'token' } }
        Mock Exit-LabRunLock {}
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
        Assert-MockCalled Enter-LabRunLock -Times 2 -Exactly -Scope It
        Assert-MockCalled Exit-LabRunLock -Times 2 -Exactly -Scope It
    }
}
