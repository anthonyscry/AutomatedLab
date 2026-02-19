Set-StrictMode -Version Latest

Describe 'Action result contract' {
    BeforeAll {
        $corePublicPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabActionResult.ps1'
        $domainPublicPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Domain/Public/Resolve-LabFailureCategory.ps1'

        . $corePublicPath
        . $domainPublicPath
    }

    It 'includes baseline properties and required contract fields' {
        $result = New-LabActionResult -Action 'deploy' -RequestedMode 'full'

        $result.PSObject.Properties.Name | Should -Contain 'RunId'
        $result.PSObject.Properties.Name | Should -Contain 'Action'
        $result.PSObject.Properties.Name | Should -Contain 'RequestedMode'
        $result.PSObject.Properties.Name | Should -Contain 'EffectiveMode'
        $result.PSObject.Properties.Name | Should -Contain 'PolicyOutcome'
        $result.PSObject.Properties.Name | Should -Contain 'Succeeded'
        $result.PSObject.Properties.Name | Should -Contain 'FailureCategory'
        $result.PSObject.Properties.Name | Should -Contain 'ErrorCode'
        $result.PSObject.Properties.Name | Should -Contain 'RecoveryHint'
        $result.PSObject.Properties.Name | Should -Contain 'ArtifactPath'
        $result.PSObject.Properties.Name | Should -Contain 'DurationMs'
    }

    It 'returns a stable typed result contract with defaults' {
        $result = New-LabActionResult -Action 'deploy' -RequestedMode 'full'

        $parsedGuid = [guid]::Empty

        @($result.PSObject.Properties.Name) | Should -Be @(
            'RunId',
            'Action',
            'RequestedMode',
            'EffectiveMode',
            'PolicyOutcome',
            'Succeeded',
            'FailureCategory',
            'ErrorCode',
            'RecoveryHint',
            'ArtifactPath',
            'DurationMs'
        )
        [guid]::TryParse($result.RunId, [ref]$parsedGuid) | Should -BeTrue

        $result.Action | Should -BeOfType [string]
        $result.RequestedMode | Should -BeOfType [string]
        $result.EffectiveMode | Should -BeOfType [string]
        $result.PolicyOutcome | Should -BeOfType [string]
        $result.Succeeded | Should -BeOfType [bool]
        $result.DurationMs | Should -BeOfType [int]

        $result.EffectiveMode | Should -Be 'full'
        $result.PolicyOutcome | Should -Be 'Approved'
        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -BeNullOrEmpty
        $result.ErrorCode | Should -BeNullOrEmpty
        $result.RecoveryHint | Should -BeNullOrEmpty
        $result.ArtifactPath | Should -BeNullOrEmpty
        $result.DurationMs | Should -Be 0
    }

    It 'validates action result inputs defensively' {
        { New-LabActionResult -Action '' -RequestedMode 'full' } | Should -Throw
        { New-LabActionResult -Action 'deploy' -RequestedMode '' } | Should -Throw
    }

    It 'maps common exception types to failure categories' {
        Resolve-LabFailureCategory -Exception ([System.UnauthorizedAccessException]::new('denied')) | Should -Be 'PolicyBlocked'
        Resolve-LabFailureCategory -Exception ([System.TimeoutException]::new('slow')) | Should -Be 'TimeoutExceeded'
        Resolve-LabFailureCategory -Exception ([System.ArgumentException]::new('bad arg')) | Should -Be 'ConfigError'
    }

    It 'validates failure category inputs defensively' {
        { Resolve-LabFailureCategory -Exception $null } | Should -Throw
    }

    It 'maps unknown exceptions to UnexpectedException' {
        $err = [System.Exception]::new('boom')

        Resolve-LabFailureCategory -Exception $err | Should -Be 'UnexpectedException'
    }
}
