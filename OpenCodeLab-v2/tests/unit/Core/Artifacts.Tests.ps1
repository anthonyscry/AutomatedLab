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

        Get-Content -Path $set.RunFilePath -Raw | Should -Be '{}'
        (Get-Item -Path $set.EventsFilePath).Length | Should -Be 0
        (Get-Item -Path $set.SummaryFilePath).Length | Should -Be 0
    }

    It 'rejects RunId values that traverse outside LogRoot' {
        $root = Join-Path -Path $TestDrive -ChildPath 'logs'

        { New-LabRunArtifactSet -LogRoot $root -RunId '..' } | Should -Throw -ExpectedMessage 'RunId must resolve within LogRoot'
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

    It 'keeps generated timestamp when Event includes timestamp field' {
        $root = Join-Path -Path $TestDrive -ChildPath 'logs'
        $set = New-LabRunArtifactSet -LogRoot $root -RunId 'run-3'

        $result = Write-LabEvent -ArtifactSet $set -Event @{ type = 'step'; timestamp = 'override' }

        $result.timestamp | Should -Not -Be 'override'
        ([DateTimeOffset]::Parse($result.timestamp).Offset.TotalMinutes) | Should -Be 0

        $line = (Get-Content -Path $set.EventsFilePath | Select-Object -First 1) | ConvertFrom-Json
        $line.timestamp | Should -Not -Be 'override'
    }

    It 'rejects scalar event values' {
        $root = Join-Path -Path $TestDrive -ChildPath 'logs'
        $set = New-LabRunArtifactSet -LogRoot $root -RunId 'run-4'

        { Write-LabEvent -ArtifactSet $set -Event 'bad-event' } | Should -Throw -ExpectedMessage 'Event must be a dictionary or object with named properties'
    }

    It 'throws when ArtifactSet.EventsFilePath is missing' {
        { Write-LabEvent -ArtifactSet ([pscustomobject]@{}) -Event @{ type = 'step' } } | Should -Throw -ExpectedMessage 'ArtifactSet.EventsFilePath is required'
    }
}
