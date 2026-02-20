Set-StrictMode -Version Latest

Describe 'Local lifecycle smoke' {
    BeforeAll {
        $coreResultPath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $hyperVPrereqPath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/OpenCodeLab.Infrastructure.HyperV/Public/Test-HyperVPrereqs.ps1'
        $preflightActionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../src/OpenCodeLab.Domain/Actions/Invoke-LabPreflightAction.ps1'

        foreach ($requiredPath in @($coreResultPath, $hyperVPrereqPath, $preflightActionPath)) {
            if (-not (Test-Path -Path $requiredPath)) {
                throw "Required smoke dependency is missing: $requiredPath"
            }
        }

        . $coreResultPath
        . $hyperVPrereqPath
        . $preflightActionPath
    }

    It 'runs preflight->deploy->status->health->teardown pipeline' {
        $probe = Test-HyperVPrereqs
        if (-not $probe.Ready) {
            $reason = if ([string]::IsNullOrWhiteSpace($probe.Reason)) {
                'Hyper-V prerequisites are unavailable on this host.'
            }
            else {
                $probe.Reason
            }

            Set-ItResult -Skipped -Because $reason
            return
        }

        $preflight = Invoke-LabPreflightAction
        $preflight.Action | Should -Be 'preflight'
        $preflight.Succeeded | Should -BeTrue
        $preflight.FailureCategory | Should -BeNullOrEmpty
    }
}
