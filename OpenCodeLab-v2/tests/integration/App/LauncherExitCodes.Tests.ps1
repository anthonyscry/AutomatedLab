Set-StrictMode -Version Latest

Describe 'Launcher process exit codes' {
    BeforeAll {
        $launcherPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../scripts/opencodelab.ps1'
        if (-not (Test-Path -Path $launcherPath)) {
            throw "Launcher script not found: $launcherPath"
        }
    }

    BeforeEach {
        $logRoot = Join-Path -Path $TestDrive -ChildPath 'logs'
        $configPath = Join-Path -Path $TestDrive -ChildPath 'lab.settings.psd1'

        @"
@{
    Lab = @{ Name = 'OpenCodeLab-v2' }
    Paths = @{ LogRoot = '$logRoot' }
}
"@ | Set-Content -Path $configPath -Encoding utf8
    }

    It 'returns mapped config-style exit code for unsupported commands' {
        & pwsh -NoProfile -File $launcherPath -Command unsupported-command -ConfigPath $configPath | Out-Null
        $LASTEXITCODE | Should -Be 3
    }

    It 'returns config error exit code when config cannot be loaded' {
        $missingConfigPath = Join-Path -Path $TestDrive -ChildPath 'missing.settings.psd1'

        & pwsh -NoProfile -File $launcherPath -Command dashboard -ConfigPath $missingConfigPath | Out-Null
        $LASTEXITCODE | Should -Be 3
    }

    It 'returns policy blocked exit code when teardown is blocked' {
        & pwsh -NoProfile -File $launcherPath -Command teardown -Mode full -ConfigPath $configPath | Out-Null
        $LASTEXITCODE | Should -Be 2
    }

    It 'returns success exit code for successful command execution' {
        & pwsh -NoProfile -File $launcherPath -Command dashboard -ConfigPath $configPath | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
