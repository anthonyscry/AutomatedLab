# Entry-doc coverage tests (DOC-01)
# Asserts that README and GETTING-STARTED.md remain aligned with current CLI/GUI behavior.
# Anchored to key phrases -- update these tests when documented behavior changes.

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $readmePath = Join-Path $repoRoot 'README.md'
    $gettingStartedPath = Join-Path (Join-Path $repoRoot 'docs') 'GETTING-STARTED.md'
    $secretsPath = Join-Path $repoRoot 'SECRETS-BOOTSTRAP.md'
}

Describe 'README entry-point coverage' {

    It 'README documents one-button-setup entry point' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match ([regex]::Escape('one-button-setup'))
    }

    It 'README documents non-interactive deploy quick and teardown full patterns' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match ([regex]::Escape('-Action deploy -Mode quick'))
        $content | Should -Match ([regex]::Escape('-Action teardown -Mode full'))
        $content | Should -Match ([regex]::Escape('-NonInteractive'))
        $content | Should -Match ([regex]::Escape('-Force'))
    }

    It 'README documents all three DispatchMode values with examples' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match 'DispatchMode'
        $content | Should -Match ([regex]::Escape('DispatchMode off'))
        $content | Should -Match ([regex]::Escape('DispatchMode canary'))
        $content | Should -Match ([regex]::Escape('DispatchMode enforced'))
    }

    It 'README documents DispatchMode precedence over OPENCODELAB_DISPATCH_MODE' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match 'OPENCODELAB_DISPATCH_MODE'
        $content | Should -Match '(?i)explicit\s+`-DispatchMode`\s+takes\s+precedence'
    }

    It 'README documents OpenCode /run alias and OpenCodeLab-GUI.ps1 GUI entry' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match ([regex]::Escape('/run'))
        $content | Should -Match ([regex]::Escape('OpenCodeLab-GUI.ps1'))
    }

    It 'README documents add-lin1 action' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match ([regex]::Escape('add-lin1'))
    }

    It 'README links to Getting Started onboarding guide' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match '\[Getting Started\]'
        $content | Should -Match 'GETTING-STARTED'
    }

    It 'README links to SECRETS-BOOTSTRAP.md' {
        $content = Get-Content -Path $readmePath -Raw
        $content | Should -Match ([regex]::Escape('SECRETS-BOOTSTRAP.md'))
    }

}

Describe 'GETTING-STARTED.md onboarding guide coverage' {

    It 'GETTING-STARTED.md exists' {
        Test-Path -Path $gettingStartedPath | Should -BeTrue
    }

    It 'GETTING-STARTED.md has at least 120 lines' {
        $lines = Get-Content -Path $gettingStartedPath
        $lines.Count | Should -BeGreaterOrEqual 120
    }

    It 'GETTING-STARTED.md contains First Run section' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match '(?i)First Run'
    }

    It 'GETTING-STARTED.md contains Quick Reference section' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match '(?i)Quick Reference'
    }

    It 'GETTING-STARTED.md contains Failure Recovery section' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match '(?i)Failure Recovery'
    }

    It 'GETTING-STARTED.md includes one-button-setup example' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match ([regex]::Escape('one-button-setup'))
    }

    It 'GETTING-STARTED.md includes deploy quick example' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match ([regex]::Escape('-Action deploy -Mode quick'))
    }

    It 'GETTING-STARTED.md includes health action example' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match ([regex]::Escape('-Action health'))
    }

    It 'GETTING-STARTED.md includes rollback mention in recovery section' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match '(?i)rollback'
    }

    It 'GETTING-STARTED.md cross-links back to README.md' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match 'README\.md'
    }

    It 'GETTING-STARTED.md references SECRETS-BOOTSTRAP.md for secret setup' {
        $content = Get-Content -Path $gettingStartedPath -Raw
        $content | Should -Match 'SECRETS-BOOTSTRAP\.md'
    }

}

Describe 'Cross-document consistency' {

    It 'SECRETS-BOOTSTRAP.md exists' {
        Test-Path -Path $secretsPath | Should -BeTrue
    }

    It 'SECRETS-BOOTSTRAP.md documents OPENCODELAB_ADMIN_PASSWORD requirement' {
        $content = Get-Content -Path $secretsPath -Raw
        $content | Should -Match 'OPENCODELAB_ADMIN_PASSWORD'
    }

    It 'README and GETTING-STARTED.md both document OPENCODELAB_ADMIN_PASSWORD secret setup' {
        $readmeContent = Get-Content -Path $readmePath -Raw
        $gsContent = Get-Content -Path $gettingStartedPath -Raw

        $readmeContent | Should -Match 'OPENCODELAB_ADMIN_PASSWORD'
        $gsContent | Should -Match 'OPENCODELAB_ADMIN_PASSWORD'
    }

}
