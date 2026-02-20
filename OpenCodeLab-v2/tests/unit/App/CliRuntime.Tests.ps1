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
}
