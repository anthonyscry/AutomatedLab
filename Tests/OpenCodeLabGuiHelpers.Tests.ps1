# OpenCodeLab GUI helper tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/New-LabAppArgumentList.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabRunArtifactSummary.ps1')
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
}
