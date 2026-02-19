Set-StrictMode -Version Latest

Describe 'Lab config' {
    BeforeAll {
        $schemaPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/Test-LabConfigSchema.ps1'
        $loaderPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/Get-LabConfig.ps1'

        if (Test-Path -Path $schemaPath) {
            . $schemaPath
        }

        if (Test-Path -Path $loaderPath) {
            . $loaderPath
        }
    }

    It 'rejects config missing required keys' {
        $cfg = @{ Lab = @{ Name = 'x' } }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Missing required key: Paths.LogRoot'
    }

    It 'loads default config and validates schema' {
        $configPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../config/lab.settings.psd1'

        $cfg = Get-LabConfig -Path $configPath

        $cfg.Paths.LogRoot | Should -Not -BeNullOrEmpty
    }
}
