# OpenCodeLab GUI helper tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/New-LabAppArgumentList.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabRunArtifactSummary.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabGuiDestructiveGuard.ps1')
}

Describe 'New-LabGuiCommandPreview' {
    It 'builds a readable preview command from options' {
        $options = @{
            Action = 'deploy'
            Mode = 'quick'
            NonInteractive = $true
            DryRun = $true
            ProfilePath = 'C:\Profiles\quick.json'
            CoreOnly = $true
        }

        $result = New-LabGuiCommandPreview -AppScriptPath 'C:\Lab\OpenCodeLab-App.ps1' -Options $options

        $result | Should -Be ".\\OpenCodeLab-App.ps1 -Action deploy -Mode quick -NonInteractive -DryRun -ProfilePath 'C:\Profiles\quick.json' -CoreOnly"
    }
}

Describe 'Get-LabLatestRunArtifactPath' {
    It 'prefers newest json artifact over txt' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        try {
            $txtPath = Join-Path $root 'OpenCodeLab-Run-20260101-010101.txt'
            $jsonPath = Join-Path $root 'OpenCodeLab-Run-20260101-020202.json'

            Set-Content -Path $txtPath -Value 'success: True' -Encoding UTF8
            Set-Content -Path $jsonPath -Value '{"success":true}' -Encoding UTF8

            $result = Get-LabLatestRunArtifactPath -LogRoot $root

            $result | Should -Be $jsonPath
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'filters by SinceUtc and excludes known pre-run artifacts' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        try {
            $oldJson = Join-Path $root 'OpenCodeLab-Run-20260101-010101.json'
            $newTxt = Join-Path $root 'OpenCodeLab-Run-20260101-030303.txt'
            $newJson = Join-Path $root 'OpenCodeLab-Run-20260101-040404.json'

            Set-Content -Path $oldJson -Value '{"success":true}' -Encoding UTF8
            Set-Content -Path $newTxt -Value 'success: True' -Encoding UTF8
            Set-Content -Path $newJson -Value '{"success":false}' -Encoding UTF8

            (Get-Item -Path $oldJson).LastWriteTimeUtc = [datetime]'2026-01-01T01:01:01Z'
            (Get-Item -Path $newTxt).LastWriteTimeUtc = [datetime]'2026-01-01T03:03:03Z'
            (Get-Item -Path $newJson).LastWriteTimeUtc = [datetime]'2026-01-01T04:04:04Z'

            $result = Get-LabLatestRunArtifactPath -LogRoot $root -SinceUtc ([datetime]'2026-01-01T03:00:00Z') -ExcludeArtifactPaths @($newJson)

            $result | Should -Be $newTxt
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-LabRunArtifactSummary' {
    It 'parses json artifact status and action' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        try {
            $jsonPath = Join-Path $root 'OpenCodeLab-Run-20260101-020202.json'
            $payload = @{
                run_id = '20260101-020202'
                action = 'teardown'
                effective_mode = 'quick'
                success = $false
                duration_seconds = 42
                ended_utc = '2026-01-01T02:02:02Z'
                error = 'sample failure'
            } | ConvertTo-Json

            Set-Content -Path $jsonPath -Value $payload -Encoding UTF8

            $summary = Get-LabRunArtifactSummary -ArtifactPath $jsonPath

            $summary.RunId | Should -Be '20260101-020202'
            $summary.Action | Should -Be 'teardown'
            $summary.Mode | Should -Be 'quick'
            $summary.Success | Should -BeFalse
            $summary.Error | Should -Be 'sample failure'
            $summary.SummaryText | Should -Match 'FAILED'
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'parses txt artifact values and builds success summary' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        try {
            $txtPath = Join-Path $root 'OpenCodeLab-Run-20260101-020202.txt'
            @(
                'run_id: 20260101-020202'
                'action: deploy'
                'effective_mode: full'
                'success: yes'
                'duration_seconds: 13'
                'ended_utc: 2026-01-01T02:02:02Z'
            ) | Set-Content -Path $txtPath -Encoding UTF8

            $summary = Get-LabRunArtifactSummary -ArtifactPath $txtPath

            $summary.RunId | Should -Be '20260101-020202'
            $summary.Action | Should -Be 'deploy'
            $summary.Mode | Should -Be 'full'
            $summary.Success | Should -BeTrue
            $summary.DurationSeconds | Should -Be 13
            $summary.SummaryText | Should -Match 'SUCCESS'
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when artifact is missing' {
        { Get-LabRunArtifactSummary -ArtifactPath 'C:\Nope\OpenCodeLab-Run-20260101-000000.json' } | Should -Throw '*Artifact not found*'
    }

    It 'throws a clear error for malformed json artifacts' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        try {
            $jsonPath = Join-Path $root 'OpenCodeLab-Run-20260101-020202.json'
            Set-Content -Path $jsonPath -Value '{ not-json }' -Encoding UTF8

            { Get-LabRunArtifactSummary -ArtifactPath $jsonPath } | Should -Throw '*Invalid run artifact JSON*'
        }
        finally {
            Remove-Item -Path $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-LabGuiDestructiveGuard' {
    It 'marks blow-away as destructive regardless of mode' {
        $result = Get-LabGuiDestructiveGuard -Action 'blow-away' -Mode 'quick'

        $result.RequiresConfirmation | Should -BeTrue
        $result.RecommendedNonInteractiveDefault | Should -BeFalse
        $result.ConfirmationLabel | Should -Be 'BLOW AWAY'
    }

    It 'marks full teardown as destructive' {
        $result = Get-LabGuiDestructiveGuard -Action 'teardown' -Mode 'full'

        $result.RequiresConfirmation | Should -BeTrue
        $result.RecommendedNonInteractiveDefault | Should -BeFalse
        $result.ConfirmationLabel | Should -Be 'FULL TEARDOWN'
    }

    It 'does not mark quick teardown as destructive' {
        $result = Get-LabGuiDestructiveGuard -Action 'teardown' -Mode 'quick'

        $result.RequiresConfirmation | Should -BeFalse
        $result.RecommendedNonInteractiveDefault | Should -BeTrue
    }

    It 'does not mark deploy as destructive' {
        $result = Get-LabGuiDestructiveGuard -Action 'deploy' -Mode 'full'

        $result.RequiresConfirmation | Should -BeFalse
        $result.RecommendedNonInteractiveDefault | Should -BeTrue
    }
}
