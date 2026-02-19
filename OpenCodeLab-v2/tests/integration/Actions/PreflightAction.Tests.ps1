Set-StrictMode -Version Latest

Describe 'Preflight action' {
    BeforeAll {
        $coreResultPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $actionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Actions/Invoke-LabPreflightAction.ps1'
        $hyperVPrereqPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Infrastructure.HyperV/Public/Test-HyperVPrereqs.ps1'

        . $coreResultPath

        if (Test-Path -Path $hyperVPrereqPath) {
            . $hyperVPrereqPath
        }

        if (Test-Path -Path $actionPath) {
            . $actionPath
        }
    }

    It 'returns PreflightFailed when Hyper-V prerequisites are not ready' {
        Mock Test-HyperVPrereqs {
            return @{
                Ready = $false
                Reason = 'Hyper-V disabled'
            }
        }

        $result = Invoke-LabPreflightAction

        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'PreflightFailed'
        $result.RecoveryHint | Should -Match 'Enable Hyper-V'

        $result.Action | Should -Be 'preflight'
        $result.RequestedMode | Should -Be 'full'
        $result.PolicyOutcome | Should -Be 'Approved'
    }
}
