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
        $result.ErrorCode | Should -Be 'CONFIRMATION_REQUIRED'
    }
}
