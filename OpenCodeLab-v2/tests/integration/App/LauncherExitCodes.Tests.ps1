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

    It 'returns startup/import exit code when module import fails before command routing' {
        $isolatedRoot = Join-Path -Path $TestDrive -ChildPath 'isolated-launcher'
        $scriptsPath = Join-Path -Path $isolatedRoot -ChildPath 'scripts'
        $null = New-Item -Path $scriptsPath -ItemType Directory -Force

        $copiedLauncherPath = Join-Path -Path $scriptsPath -ChildPath 'opencodelab.ps1'
        $launcherContent = Get-Content -Path $launcherPath -Raw
        $launcherContent = $launcherContent -replace [regex]::Escape("../src/OpenCodeLab.App/OpenCodeLab.App.psd1"), "../src/OpenCodeLab.App/DoesNotExist.psd1"
        Set-Content -Path $copiedLauncherPath -Value $launcherContent -Encoding utf8

        & pwsh -NoProfile -File $copiedLauncherPath -Command dashboard -ConfigPath $configPath | Out-Null
        $LASTEXITCODE | Should -Be 3
    }

    It 'creates startup failure artifact files and reports artifact path in process output' {
        $isolatedRoot = Join-Path -Path $TestDrive -ChildPath 'isolated-launcher-artifacts'
        $scriptsPath = Join-Path -Path $isolatedRoot -ChildPath 'scripts'
        $null = New-Item -Path $scriptsPath -ItemType Directory -Force

        $copiedLauncherPath = Join-Path -Path $scriptsPath -ChildPath 'opencodelab.ps1'
        $launcherContent = Get-Content -Path $launcherPath -Raw
        $launcherContent = $launcherContent -replace [regex]::Escape("../src/OpenCodeLab.App/OpenCodeLab.App.psd1"), "../src/OpenCodeLab.App/DoesNotExist.psd1"
        Set-Content -Path $copiedLauncherPath -Value $launcherContent -Encoding utf8

        $json = & pwsh -NoProfile -File $copiedLauncherPath -Command dashboard -ConfigPath $configPath -Output json | Out-String
        $LASTEXITCODE | Should -Be 3

        $parsed = $json | ConvertFrom-Json
        $parsed.ArtifactPath | Should -Not -BeNullOrEmpty
        Test-Path -Path $parsed.ArtifactPath | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'run.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'summary.txt') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'errors.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'events.jsonl') | Should -BeTrue
    }

    It 'falls back to default startup artifact location when config is malformed during import failure' {
        $isolatedRoot = Join-Path -Path $TestDrive -ChildPath 'isolated-launcher-malformed-config'
        $scriptsPath = Join-Path -Path $isolatedRoot -ChildPath 'scripts'
        $null = New-Item -Path $scriptsPath -ItemType Directory -Force

        $malformedConfigPath = Join-Path -Path $TestDrive -ChildPath 'malformed.settings.psd1'
        '@{ Paths = ' | Set-Content -Path $malformedConfigPath -Encoding utf8

        $copiedLauncherPath = Join-Path -Path $scriptsPath -ChildPath 'opencodelab.ps1'
        $launcherContent = Get-Content -Path $launcherPath -Raw
        $launcherContent = $launcherContent -replace [regex]::Escape("../src/OpenCodeLab.App/OpenCodeLab.App.psd1"), "../src/OpenCodeLab.App/DoesNotExist.psd1"
        Set-Content -Path $copiedLauncherPath -Value $launcherContent -Encoding utf8

        $rawOutput = (& pwsh -NoProfile -File $copiedLauncherPath -Command dashboard -ConfigPath $malformedConfigPath -Output json 2>&1 | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        $LASTEXITCODE | Should -Be 3
        $rawOutput | Should -Not -Match 'Import-PowerShellDataFile'

        $parsed = $rawOutput | ConvertFrom-Json
        $parsed.ArtifactPath | Should -Not -BeNullOrEmpty
        Test-Path -Path $parsed.ArtifactPath | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'run.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'summary.txt') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'errors.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $parsed.ArtifactPath -ChildPath 'events.jsonl') | Should -BeTrue
    }
}
