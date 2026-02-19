Set-StrictMode -Version Latest

Describe 'Artifact writer' {
    BeforeAll {
        $artifactPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/New-LabRunArtifactSet.ps1'
        $eventPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/Write-LabEvent.ps1'

        if (Test-Path -Path $artifactPath) {
            . $artifactPath
        }

        if (Test-Path -Path $eventPath) {
            . $eventPath
        }
    }

    It 'creates run.json events.jsonl summary.txt and returns path metadata' {
        $root = Join-Path -Path $TestDrive -ChildPath 'logs'

        $set = New-LabRunArtifactSet -LogRoot $root -RunId 'run-1'

        Test-Path -Path $set.Path | Should -BeTrue
        Test-Path -Path $set.RunFilePath | Should -BeTrue
        Test-Path -Path $set.EventsFilePath | Should -BeTrue
        Test-Path -Path $set.SummaryFilePath | Should -BeTrue

        Split-Path -Path $set.RunFilePath -Leaf | Should -Be 'run.json'
        Split-Path -Path $set.EventsFilePath -Leaf | Should -Be 'events.jsonl'
        Split-Path -Path $set.SummaryFilePath -Leaf | Should -Be 'summary.txt'
    }

    It 'writes newline-delimited event records to events.jsonl' {
        $root = Join-Path -Path $TestDrive -ChildPath 'logs'
        $set = New-LabRunArtifactSet -LogRoot $root -RunId 'run-2'

        Write-LabEvent -ArtifactSet $set -Event @{ type = 'step'; status = 'ok' }
        Write-LabEvent -ArtifactSet $set -Event @{ type = 'step'; status = 'done' }

        $lines = Get-Content -Path $set.EventsFilePath
        $lines.Count | Should -Be 2

        $first = $lines[0] | ConvertFrom-Json
        $second = $lines[1] | ConvertFrom-Json

        $first.type | Should -Be 'step'
        $first.status | Should -Be 'ok'
        $first.timestamp | Should -Not -BeNullOrEmpty

        $second.status | Should -Be 'done'
    }
}
