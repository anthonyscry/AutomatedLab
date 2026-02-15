# OpenCodeLab GUI helper tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/New-LabAppArgumentList.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabRunArtifactSummary.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabGuiDestructiveGuard.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabGuiLayoutState.ps1')
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

    It 'includes target hosts and confirmation token in preview when provided' {
        $options = @{
            Action = 'teardown'
            Mode = 'full'
            NonInteractive = $true
            TargetHosts = @('hv-a', 'hv-b')
            ConfirmationToken = 'scope-token-001'
        }

        $result = New-LabGuiCommandPreview -AppScriptPath 'C:\Lab\OpenCodeLab-App.ps1' -Options $options

        $result | Should -Be ".\\OpenCodeLab-App.ps1 -Action teardown -Mode full -NonInteractive -TargetHosts hv-a hv-b -ConfirmationToken scope-token-001"
    }
}

Describe 'New-LabAppArgumentList' {
    It 'adds target hosts and confirmation token arguments when provided' {
        $options = @{
            Action = 'teardown'
            Mode = 'full'
            TargetHosts = @('hv-a', 'hv-b')
            ConfirmationToken = 'scope-token-001'
        }

        $result = New-LabAppArgumentList -Options $options

        $result | Should -Be @('-Action', 'teardown', '-Mode', 'full', '-TargetHosts', 'hv-a', 'hv-b', '-ConfirmationToken', 'scope-token-001')
    }

    It 'normalizes target hosts from mixed delimiters and whitespace' {
        $options = @{
            Action = 'teardown'
            Mode = 'full'
            TargetHosts = @(' hv-a, hv-b ', 'hv-c;  hv-d', '   ')
        }

        $result = New-LabAppArgumentList -Options $options

        $result | Should -Be @('-Action', 'teardown', '-Mode', 'full', '-TargetHosts', 'hv-a', 'hv-b', 'hv-c', 'hv-d')
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

    It 'marks one-button-reset as destructive' {
        $result = Get-LabGuiDestructiveGuard -Action 'one-button-reset' -Mode 'quick'

        $result.RequiresConfirmation | Should -BeTrue
        $result.RecommendedNonInteractiveDefault | Should -BeFalse
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

    It 'marks quick teardown with profile path as potentially destructive' {
        $result = Get-LabGuiDestructiveGuard -Action 'teardown' -Mode 'quick' -ProfilePath 'C:\Profiles\override.json'

        $result.RequiresConfirmation | Should -BeTrue
        $result.RecommendedNonInteractiveDefault | Should -BeFalse
        $result.ConfirmationLabel | Should -Be 'POTENTIAL FULL TEARDOWN'
    }

    It 'does not mark deploy as destructive' {
        $result = Get-LabGuiDestructiveGuard -Action 'deploy' -Mode 'full'

        $result.RequiresConfirmation | Should -BeFalse
        $result.RecommendedNonInteractiveDefault | Should -BeTrue
    }
}

Describe 'Get-LabGuiLayoutState' {
    It 'keeps advanced panel hidden for quick default teardown without target hosts' {
        $result = Get-LabGuiLayoutState -Action 'deploy' -Mode 'quick' -ProfilePath ''

        $result.ShowAdvanced | Should -BeFalse
        $result.AdvancedForDestructiveAction | Should -BeFalse
        $result.HasTargetHosts | Should -BeFalse
        $result.RecommendedNonInteractiveDefault | Should -BeTrue
    }

    It 'auto-opens advanced controls for destructive actions' {
        $result = Get-LabGuiLayoutState -Action 'teardown' -Mode 'full' -ProfilePath ''

        $result.ShowAdvanced | Should -BeTrue
        $result.AdvancedForDestructiveAction | Should -BeTrue
    }

    It 'flags target host input as a reason to open advanced controls' {
        $result = Get-LabGuiLayoutState -Action 'deploy' -Mode 'quick' -ProfilePath '' -TargetHosts @('hv-a,hv-b')

        $result.ShowAdvanced | Should -BeTrue
        $result.HasTargetHosts | Should -BeTrue
        $result.AdvancedForDestructiveAction | Should -BeFalse
    }
}
