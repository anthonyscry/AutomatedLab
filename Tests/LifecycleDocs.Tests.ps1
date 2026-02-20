# Documentation coverage tests for DOC-02 and DOC-03
# Protects lifecycle user guide and troubleshooting playbook content

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $lifecyclePath = Join-Path $repoRoot 'docs/LIFECYCLE-WORKFLOWS.md'
    $runbookPath   = Join-Path $repoRoot 'RUNBOOK-ROLLBACK.md'
}

Describe 'Lifecycle workflow guide (DOC-02)' {

    It 'lifecycle guide file exists' {
        Test-Path -Path $lifecyclePath | Should -BeTrue
    }

    It 'lifecycle guide covers bootstrap workflow' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match '(?i)bootstrap'
        $content | Should -Match 'one-button-setup'
        $content | Should -Match '-NonInteractive'
    }

    It 'lifecycle guide covers deploy workflow with quick and full modes' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match '(?i)deploy'
        $content | Should -Match '-Mode quick'
        $content | Should -Match '-Mode full'
    }

    It 'lifecycle guide covers quick mode auto-heal fallback and escalation' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match '(?i)Quick Mode'
        $content | Should -Match '(?i)auto.heal'
        $content | Should -Match 'EscalationRequired'
        $content | Should -Match 'fallback'
    }

    It 'lifecycle guide covers teardown workflow' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match '(?i)Teardown'
        $content | Should -Match 'ConfirmationToken'
    }

    It 'lifecycle guide covers status and health verification' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match '(?i)Status'
        $content | Should -Match '(?i)health'
        $content | Should -Match '-Action status'
        $content | Should -Match '-Action health'
    }

    It 'lifecycle guide documents expected outcome fields' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match 'ExecutionOutcome'
        $content | Should -Match 'PolicyBlocked'
        $content | Should -Match 'EscalationRequired'
    }

    It 'lifecycle guide includes artifact paths to check' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match 'C:\\LabSources\\Logs'
    }

    It 'lifecycle guide documents Expected Outcomes section' {
        $content = Get-Content -Path $lifecyclePath -Raw
        $content | Should -Match '(?i)Expected Outcomes'
    }

    It 'lifecycle guide includes integration verification sanity flow' {
        $content = Get-Content -Path $lifecyclePath -Raw
        # Must document a manual or scripted integration check step
        $content | Should -Match '(?i)(integration verification|sanity flow|verification)'
        $content | Should -Match 'ExecutionOutcome'
    }

    It 'lifecycle guide meets minimum length requirement' {
        $lineCount = (Get-Content -Path $lifecyclePath).Count
        $lineCount | Should -BeGreaterThan 180
    }
}

Describe 'Rollback and troubleshooting runbook (DOC-03)' {

    It 'rollback runbook file exists' {
        Test-Path -Path $runbookPath | Should -BeTrue
    }

    It 'rollback runbook documents the rollback command' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match 'OpenCodeLab-App\.ps1 -Action rollback'
    }

    It 'rollback runbook contains at least 5 numbered failure scenarios' {
        $content = Get-Content -Path $runbookPath -Raw
        $scenarioCount = ([regex]::Matches($content, '(?m)^\s*\d+\)\s+')).Count
        $scenarioCount | Should -BeGreaterOrEqual 5
    }

    It 'rollback runbook covers VM provisioning failure' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)(provisioning|VM provision)'
    }

    It 'rollback runbook covers quick mode escalation' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)quick mode'
        $content | Should -Match 'EscalationRequired'
    }

    It 'rollback runbook covers scoped confirmation token failures' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)ConfirmationToken'
        $content | Should -Match '(?i)PolicyBlocked'
    }

    It 'rollback runbook covers missing snapshot restore path' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)snapshot'
        $content | Should -Match '(?i)(LabReady|missing snapshot)'
    }

    It 'rollback runbook covers network or inventory resolution failures' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)(network|inventory)'
    }

    It 'rollback runbook covers health check and rollback loop' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)(health check|rollback loop)'
    }

    It 'rollback runbook includes artifact reference paths' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match 'C:\\LabSources\\Logs'
    }

    It 'rollback runbook documents dispatch kill switch for rollback' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match 'DispatchMode off'
    }

    It 'rollback runbook documents Failure Matrix section' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)Failure Matrix'
    }

    It 'rollback runbook documents Rollback section heading' {
        $content = Get-Content -Path $runbookPath -Raw
        $content | Should -Match '(?i)Rollback'
    }

    It 'rollback runbook documents recovery verification commands' {
        $content = Get-Content -Path $runbookPath -Raw
        # Each scenario should have at least one confirm/verify command
        $content | Should -Match '(?i)(Confirm recovery|confirm|verify)'
        $content | Should -Match '-Action health'
    }
}
