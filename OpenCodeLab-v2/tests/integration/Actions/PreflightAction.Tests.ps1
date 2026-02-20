Set-StrictMode -Version Latest

Describe 'Preflight action' {
    BeforeAll {
        $coreResultPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $actionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Actions/Invoke-LabPreflightAction.ps1'
        $hyperVPrereqPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Infrastructure.HyperV/Public/Test-HyperVPrereqs.ps1'

        foreach ($requiredPath in @($coreResultPath, $hyperVPrereqPath, $actionPath)) {
            if (-not (Test-Path -Path $requiredPath)) {
                throw "Required test dependency is missing: $requiredPath"
            }
        }

        . $coreResultPath
        . $hyperVPrereqPath
        . $actionPath
    }

    It 'returns success when Hyper-V prerequisites are ready' {
        Mock Test-HyperVPrereqs {
            return [pscustomobject]@{
                Ready = $true
                Reason = $null
            }
        }

        $result = Invoke-LabPreflightAction

        $result.Succeeded | Should -BeTrue
        $result.FailureCategory | Should -BeNullOrEmpty
        $result.RecoveryHint | Should -BeNullOrEmpty
        $result.Action | Should -Be 'preflight'
        $result.RequestedMode | Should -Be 'full'
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
        $result.ErrorCode | Should -Be 'PREFLIGHT_PREREQ_NOT_READY'
        $result.RecoveryHint | Should -Match 'Enable Hyper-V'

        $result.Action | Should -Be 'preflight'
        $result.RequestedMode | Should -Be 'full'
        $result.PolicyOutcome | Should -Be 'Approved'
    }

    It 'uses default remediation text when reason is null or empty' {
        foreach ($reason in @($null, '')) {
            Mock Test-HyperVPrereqs {
                return [pscustomobject]@{
                    Ready = $false
                    Reason = $reason
                }
            }

            $result = Invoke-LabPreflightAction

            $result.Succeeded | Should -BeFalse
            $result.FailureCategory | Should -Be 'PreflightFailed'
            $result.ErrorCode | Should -Be 'PREFLIGHT_PREREQ_NOT_READY'
            $result.RecoveryHint | Should -Be 'Enable Hyper-V and rerun preflight.'
        }
    }

    It 'does not duplicate remediation text when reason already includes it' {
        Mock Test-HyperVPrereqs {
            return [pscustomobject]@{
                Ready = $false
                Reason = 'Hyper-V cmdlets are unavailable. Enable Hyper-V and rerun preflight.'
            }
        }

        $result = Invoke-LabPreflightAction

        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'PreflightFailed'
        $result.ErrorCode | Should -Be 'PREFLIGHT_PREREQ_NOT_READY'
        $result.RecoveryHint | Should -Be 'Hyper-V cmdlets are unavailable. Enable Hyper-V and rerun preflight.'
    }

    It 'returns classified PreflightFailed result when the probe throws' {
        Mock Test-HyperVPrereqs {
            throw 'Get-VM failed unexpectedly'
        }

        { Invoke-LabPreflightAction } | Should -Not -Throw
        $result = Invoke-LabPreflightAction

        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'PreflightFailed'
        $result.ErrorCode | Should -Be 'PREFLIGHT_PROBE_FAILED'
        $result.RecoveryHint | Should -Match 'Get-VM failed unexpectedly'
        $result.RecoveryHint | Should -Match 'Enable Hyper-V'
    }
}
