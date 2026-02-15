# Contract tests for execution metadata persistence

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $appPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'
}

Describe 'OpenCodeLab dispatch execution metadata contract' {
    BeforeEach {
        $script:originalRunLogRoot = $env:OPENCODELAB_RUN_LOG_ROOT
        $script:originalWriteArtifactsInNoExecute = $env:OPENCODELAB_WRITE_ARTIFACTS_IN_NOEXECUTE

        $artifactRoot = Join-Path $TestDrive 'artifacts'
        New-Item -Path $artifactRoot -ItemType Directory -Force | Out-Null
        $env:OPENCODELAB_RUN_LOG_ROOT = $artifactRoot
        $env:OPENCODELAB_WRITE_ARTIFACTS_IN_NOEXECUTE = '1'
    }

    AfterEach {
        if ($null -eq $script:originalRunLogRoot) {
            Remove-Item Env:OPENCODELAB_RUN_LOG_ROOT -ErrorAction SilentlyContinue
        }
        else {
            $env:OPENCODELAB_RUN_LOG_ROOT = $script:originalRunLogRoot
        }

        if ($null -eq $script:originalWriteArtifactsInNoExecute) {
            Remove-Item Env:OPENCODELAB_WRITE_ARTIFACTS_IN_NOEXECUTE -ErrorAction SilentlyContinue
        }
        else {
            $env:OPENCODELAB_WRITE_ARTIFACTS_IN_NOEXECUTE = $script:originalWriteArtifactsInNoExecute
        }
    }

    It 'emits additive execution metadata keys in JSON and txt artifacts for no-execute runs' {
        $result = & $appPath -Action status -Mode full -NoExecute

        $result.ExecutionOutcome | Should -Be 'not_dispatched'

        $artifactRoot = $env:OPENCODELAB_RUN_LOG_ROOT
        $jsonArtifact = Get-ChildItem -Path $artifactRoot -Filter 'OpenCodeLab-Run-*.json' | Select-Object -First 1
        $txtArtifact = Get-ChildItem -Path $artifactRoot -Filter 'OpenCodeLab-Run-*.txt' | Select-Object -First 1

        $jsonArtifact | Should -Not -BeNullOrEmpty
        $txtArtifact | Should -Not -BeNullOrEmpty

        $jsonData = Get-Content -Raw -Path $jsonArtifact.FullName | ConvertFrom-Json
        $jsonData.PSObject.Properties.Name | Should -Contain 'dispatch_mode'
        $jsonData.PSObject.Properties.Name | Should -Contain 'execution_outcome'
        $jsonData.PSObject.Properties.Name | Should -Contain 'execution_started_at'
        $jsonData.PSObject.Properties.Name | Should -Contain 'execution_completed_at'
        $jsonData.dispatch_mode | Should -Be 'off'
        $jsonData.execution_outcome | Should -Be 'not_dispatched'
        [string]$jsonData.execution_started_at | Should -BeNullOrEmpty
        [string]$jsonData.execution_completed_at | Should -BeNullOrEmpty

        $txtContent = Get-Content -Raw -Path $txtArtifact.FullName
        $txtContent | Should -Match '(?m)^dispatch_mode:\s*off\s*$'
        $txtContent | Should -Match '(?m)^execution_outcome:\s*not_dispatched\s*$'
        $txtContent | Should -Match '(?m)^execution_started_at:\s*$'
        $txtContent | Should -Match '(?m)^execution_completed_at:\s*$'
    }
}
