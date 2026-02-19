Set-StrictMode -Version Latest

Describe 'Status and health actions' {
    BeforeAll {
        $coreResultPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $snapshotPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Infrastructure.HyperV/Public/Get-LabVmSnapshot.ps1'
        $statusActionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Actions/Invoke-LabStatusAction.ps1'
        $healthActionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Actions/Invoke-LabHealthAction.ps1'

        foreach ($requiredPath in @($coreResultPath, $snapshotPath, $statusActionPath, $healthActionPath)) {
            if (-not (Test-Path -Path $requiredPath)) {
                throw "Required test dependency is missing: $requiredPath"
            }
        }

        . $coreResultPath
        . $snapshotPath
        . $statusActionPath
        . $healthActionPath
    }

    It 'returns VM snapshot data from status action and succeeds' {
        Mock Get-LabVmSnapshot {
            @(
                [pscustomobject]@{ Name = 'DC1'; State = 'Running' },
                [pscustomobject]@{ Name = 'SVR1'; State = 'Running' }
            )
        }

        $result = Invoke-LabStatusAction

        $result.Succeeded | Should -BeTrue
        $result.Action | Should -Be 'status'
        $result.RequestedMode | Should -Be 'full'
        $result.Data | Should -Not -BeNullOrEmpty
        $result.Data.Count | Should -Be 2
        $result.Data[0].Name | Should -Be 'DC1'
        Assert-MockCalled Get-LabVmSnapshot -Times 1 -Exactly -Scope It
    }

    It 'fails health action with VM_NOT_RUNNING when any VM is not running' {
        Mock Get-LabVmSnapshot {
            @(
                [pscustomobject]@{ Name = 'DC1'; State = 'Running' },
                [pscustomobject]@{ Name = 'WS1'; State = 'Off' }
            )
        }

        $result = Invoke-LabHealthAction

        $result.Succeeded | Should -BeFalse
        $result.Action | Should -Be 'health'
        $result.ErrorCode | Should -Be 'VM_NOT_RUNNING'
        $result.FailureCategory | Should -Be 'OperationFailed'
        Assert-MockCalled Get-LabVmSnapshot -Times 1 -Exactly -Scope It
    }

    It 'returns success when all VMs are running' {
        Mock Get-LabVmSnapshot {
            @(
                [pscustomobject]@{ Name = 'DC1'; State = 'Running' },
                [pscustomobject]@{ Name = 'SVR1'; State = 'Running' },
                [pscustomobject]@{ Name = 'WS1'; State = 'Running' }
            )
        }

        $result = Invoke-LabHealthAction

        $result.Succeeded | Should -BeTrue
        $result.ErrorCode | Should -BeNullOrEmpty
        $result.FailureCategory | Should -BeNullOrEmpty
        Assert-MockCalled Get-LabVmSnapshot -Times 1 -Exactly -Scope It
    }

    It 'returns structured failure for status when snapshot retrieval throws' {
        Mock Get-LabVmSnapshot {
            throw 'snapshot backend failed'
        }

        { Invoke-LabStatusAction } | Should -Not -Throw

        $result = Invoke-LabStatusAction

        $result.Succeeded | Should -BeFalse
        $result.Action | Should -Be 'status'
        $result.FailureCategory | Should -Be 'OperationFailed'
        $result.ErrorCode | Should -Be 'STATUS_SNAPSHOT_FAILED'
        $result.RecoveryHint | Should -Match 'snapshot backend failed'
        Assert-MockCalled Get-LabVmSnapshot -Times 2 -Exactly -Scope It
    }

    It 'returns structured failure for health when snapshot retrieval throws' {
        Mock Get-LabVmSnapshot {
            throw 'snapshot backend failed'
        }

        { Invoke-LabHealthAction } | Should -Not -Throw

        $result = Invoke-LabHealthAction

        $result.Succeeded | Should -BeFalse
        $result.Action | Should -Be 'health'
        $result.FailureCategory | Should -Be 'OperationFailed'
        $result.ErrorCode | Should -Be 'HEALTH_SNAPSHOT_FAILED'
        $result.RecoveryHint | Should -Match 'snapshot backend failed'
        Assert-MockCalled Get-LabVmSnapshot -Times 2 -Exactly -Scope It
    }

    It 'fails health action when Hyper-V tooling is unavailable' {
        Mock Get-Command {
            $null
        } -ParameterFilter { $Name -eq 'Get-VM' }

        $result = Invoke-LabHealthAction

        $result.Succeeded | Should -BeFalse
        $result.Action | Should -Be 'health'
        $result.FailureCategory | Should -Be 'OperationFailed'
        $result.ErrorCode | Should -Be 'HYPERV_TOOLING_UNAVAILABLE'
        $result.RecoveryHint | Should -Match 'Get-VM'
    }
}
