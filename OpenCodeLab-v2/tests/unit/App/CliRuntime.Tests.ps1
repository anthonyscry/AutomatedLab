Set-StrictMode -Version Latest

Describe 'CLI runtime execution' {
    BeforeAll {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.App/OpenCodeLab.App.psd1'
        Import-Module $moduleManifestPath -Force
    }

    It 'writes run artifact files and start/finish events for a command execution' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'lab.settings.psd1'
        $logRoot = Join-Path -Path $TestDrive -ChildPath 'logs'

        @"
@{
    Lab = @{ Name = 'OpenCodeLab-v2' }
    Paths = @{ LogRoot = '$logRoot' }
}
"@ | Set-Content -Path $configPath -Encoding utf8

        $result = Invoke-LabCliCommand -Command dashboard -ConfigPath $configPath

        $result.ArtifactPath | Should -Not -BeNullOrEmpty
        $result.DurationMs | Should -BeGreaterOrEqual 0

        $runFile = Join-Path -Path $result.ArtifactPath -ChildPath 'run.json'
        $summaryFile = Join-Path -Path $result.ArtifactPath -ChildPath 'summary.txt'
        $errorsFile = Join-Path -Path $result.ArtifactPath -ChildPath 'errors.json'
        $eventsFile = Join-Path -Path $result.ArtifactPath -ChildPath 'events.jsonl'

        Test-Path -Path $runFile | Should -BeTrue
        Test-Path -Path $summaryFile | Should -BeTrue
        Test-Path -Path $errorsFile | Should -BeTrue
        Test-Path -Path $eventsFile | Should -BeTrue

        $run = Get-Content -Path $runFile -Raw | ConvertFrom-Json
        $run.Action | Should -Be 'dashboard'
        $run.Succeeded | Should -BeTrue

        $summary = Get-Content -Path $summaryFile -Raw
        $summary | Should -Match 'Action: dashboard'

        $errors = Get-Content -Path $errorsFile -Raw | ConvertFrom-Json
        @($errors).Count | Should -Be 0

        $events = Get-Content -Path $eventsFile | ForEach-Object { $_ | ConvertFrom-Json }
        $events.Count | Should -BeGreaterOrEqual 2
        @($events.type) | Should -Contain 'run-started'
        @($events.type) | Should -Contain 'run-finished'
    }

    It 'creates full artifact set for unsupported commands' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'lab.settings.psd1'
        $logRoot = Join-Path -Path $TestDrive -ChildPath 'logs'

        @"
@{
    Lab = @{ Name = 'OpenCodeLab-v2' }
    Paths = @{ LogRoot = '$logRoot' }
}
"@ | Set-Content -Path $configPath -Encoding utf8

        $result = Invoke-LabCliCommand -Command unsupported-command -ConfigPath $configPath

        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'ConfigError'
        $result.ErrorCode | Should -Be 'UNSUPPORTED_COMMAND'
        $result.ArtifactPath | Should -Not -BeNullOrEmpty

        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'run.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'summary.txt') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'errors.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'events.jsonl') | Should -BeTrue
    }

    It 'creates full artifact set when config loading fails' {
        $missingConfigPath = Join-Path -Path $TestDrive -ChildPath 'missing.settings.psd1'

        $result = Invoke-LabCliCommand -Command dashboard -ConfigPath $missingConfigPath

        $result.Succeeded | Should -BeFalse
        $result.FailureCategory | Should -Be 'ConfigError'
        $result.ErrorCode | Should -Be 'CONFIG_LOAD_FAILED'
        $result.ArtifactPath | Should -Not -BeNullOrEmpty

        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'run.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'summary.txt') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'errors.json') | Should -BeTrue
        Test-Path -Path (Join-Path -Path $result.ArtifactPath -ChildPath 'events.jsonl') | Should -BeTrue
    }

    It 'passes an absolute lock path from config log root for deploy command' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'lab.settings.psd1'
        $logRoot = Join-Path -Path $TestDrive -ChildPath 'logs'

        @"
@{
    Lab = @{ Name = 'OpenCodeLab-v2' }
    Paths = @{ LogRoot = '$logRoot' }
}
"@ | Set-Content -Path $configPath -Encoding utf8

        Mock Invoke-LabDeployAction -ModuleName OpenCodeLab.App {
            New-LabActionResult -Action 'deploy' -RequestedMode $Mode
        }

        Invoke-LabCliCommand -Command deploy -ConfigPath $configPath | Out-Null

        Assert-MockCalled Invoke-LabDeployAction -ModuleName OpenCodeLab.App -Times 1 -Exactly -Scope It -ParameterFilter {
            $LockPath -eq (Join-Path -Path ([System.IO.Path]::GetFullPath((Resolve-Path -Path $logRoot).ProviderPath)) -ChildPath 'run.lock') -and
            [System.IO.Path]::IsPathRooted($LockPath)
        }
    }

    It 'passes an absolute lock path from config log root for teardown command' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'lab.settings.psd1'
        $logRoot = Join-Path -Path $TestDrive -ChildPath 'logs'

        @"
@{
    Lab = @{ Name = 'OpenCodeLab-v2' }
    Paths = @{ LogRoot = '$logRoot' }
}
"@ | Set-Content -Path $configPath -Encoding utf8

        Mock Invoke-LabTeardownAction -ModuleName OpenCodeLab.App {
            New-LabActionResult -Action 'teardown' -RequestedMode $Mode
        }

        Invoke-LabCliCommand -Command teardown -ConfigPath $configPath | Out-Null

        Assert-MockCalled Invoke-LabTeardownAction -ModuleName OpenCodeLab.App -Times 1 -Exactly -Scope It -ParameterFilter {
            $LockPath -eq (Join-Path -Path ([System.IO.Path]::GetFullPath((Resolve-Path -Path $logRoot).ProviderPath)) -ChildPath 'run.lock') -and
            [System.IO.Path]::IsPathRooted($LockPath)
        }
    }
}
