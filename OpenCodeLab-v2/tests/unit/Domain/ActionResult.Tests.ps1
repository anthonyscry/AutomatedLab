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

    It 'maps unknown exceptions to UnexpectedException' {
        $err = [System.Exception]::new('boom')

        Resolve-LabFailureCategory -Exception $err | Should -Be 'UnexpectedException'
    }
}
