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

        function Get-SmokeSkipReason {
            param(
                [Parameter(Mandatory)]
                [psobject]$Probe
            )

            $prefix = 'Hyper-V prerequisites are unavailable on this host.'
            if ([string]::IsNullOrWhiteSpace($Probe.Reason)) {
                return $prefix
            }

            return "$prefix $($Probe.Reason)"
        }
    }

    It 'captures host preflight baseline readiness details' {
        $probe = Test-HyperVPrereqs
        $probe | Should -Not -BeNullOrEmpty
        $probe.PSObject.Properties.Name | Should -Contain 'Ready'
        $probe.PSObject.Properties.Name | Should -Contain 'Reason'

        if (-not $probe.Ready) {
            $probe.Reason | Should -Not -BeNullOrEmpty
            (Get-SmokeSkipReason -Probe $probe) | Should -Match '^Hyper-V prerequisites are unavailable on this host\.'
        }
    }

    It 'runs preflight action when Hyper-V prerequisites are available' {
        $probe = Test-HyperVPrereqs
        if (-not $probe.Ready) {
            Set-ItResult -Skipped -Because (Get-SmokeSkipReason -Probe $probe)
            return
        }

        $preflight = Invoke-LabPreflightAction
        $preflight.Action | Should -Be 'preflight'
        $preflight.Succeeded | Should -BeTrue
        $preflight.FailureCategory | Should -BeNullOrEmpty
    }
}
