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

    It 'rejects config when Paths section is missing' {
        $cfg = @{ Lab = @{ Name = 'x' } }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Missing required section: Paths'
    }

    It 'rejects config when Paths is not a hashtable' {
        $cfg = @{ Lab = @{ Name = 'x' }; Paths = 'invalid' }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Invalid section type: Paths must be a hashtable'
    }

    It 'rejects config when Paths.LogRoot is missing' {
        $cfg = @{ Lab = @{ Name = 'x' }; Paths = @{} }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Missing required key: Paths.LogRoot'
    }

    It 'rejects config when Paths.LogRoot is empty' {
        $cfg = @{ Lab = @{ Name = 'x' }; Paths = @{ LogRoot = '   ' } }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Missing required key: Paths.LogRoot'
    }

    It 'rejects config when Lab section is missing' {
        $cfg = @{ Paths = @{ LogRoot = 'C:\Logs' } }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Missing required section: Lab'
    }

    It 'rejects config when Lab.Name is missing' {
        $cfg = @{ Paths = @{ LogRoot = 'C:\Logs' }; Lab = @{} }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Missing required key: Lab.Name'
    }

    It 'rejects config when Lab.Name is empty' {
        $cfg = @{ Paths = @{ LogRoot = 'C:\Logs' }; Lab = @{ Name = '  ' } }

        { Test-LabConfigSchema -Config $cfg } | Should -Throw -ExpectedMessage 'Missing required key: Lab.Name'
    }

    It 'throws when config path does not exist' {
        $missingPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../config/does-not-exist.psd1'

        { Get-LabConfig -Path $missingPath } | Should -Throw -ExpectedMessage "Config file not found: $missingPath"
    }

    It 'throws when loaded config root is not a hashtable' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Import-PowerShellDataFile -MockWith { 'invalid-root' }

        { Get-LabConfig -Path 'fake.psd1' } | Should -Throw -ExpectedMessage 'Config root must be a hashtable'
    }

    It 'loads default config and validates schema' {
        $configPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../config/lab.settings.psd1'

        $cfg = Get-LabConfig -Path $configPath

        $cfg.Paths.LogRoot | Should -Not -BeNullOrEmpty
    }
}
