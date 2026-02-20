Set-StrictMode -Version Latest

Describe 'Get-LabCommandMap' {
    BeforeAll {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.App/OpenCodeLab.App.psd1'
        $launcherPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../scripts/opencodelab.ps1'

        Import-Module $moduleManifestPath -Force
    }

    It 'exposes the required command key to handler mappings' {
        $commandMap = Get-LabCommandMap
        $expectedMap = [ordered]@{
            preflight = 'Invoke-LabPreflightAction'
            deploy    = 'Invoke-LabDeployAction'
            teardown  = 'Invoke-LabTeardownAction'
            status    = 'Invoke-LabStatusAction'
            health    = 'Invoke-LabHealthAction'
            dashboard = 'Show-LabDashboardAction'
        }

        $commandMap | Should -Not -BeNullOrEmpty
        $commandMap.Keys.Count | Should -Be $expectedMap.Keys.Count

        foreach ($key in $expectedMap.Keys) {
            $commandMap.Keys | Should -Contain $key
            $commandMap[$key] | Should -Be $expectedMap[$key]
        }
    }

    It 'executes dashboard command through launcher and returns text output by default' {
        $result = & $launcherPath -Command dashboard

        $result | Should -Match 'Action: dashboard'
        $result | Should -Match 'Succeeded: True'
        $result | Should -Match 'ArtifactPath:'
    }

    It 'supports JSON output mode through launcher' {
        $jsonResult = & $launcherPath -Command dashboard -Output json
        $parsed = $jsonResult | ConvertFrom-Json

        $parsed.Action | Should -Be 'dashboard'
        $parsed.Succeeded | Should -BeTrue
        $parsed.ArtifactPath | Should -Not -BeNullOrEmpty
    }

    It 'maps result contracts to baseline exit codes' {
        Resolve-LabExitCode -Result ([pscustomobject]@{ Succeeded = $true; FailureCategory = $null }) | Should -Be 0
        Resolve-LabExitCode -Result ([pscustomobject]@{ Succeeded = $false; FailureCategory = 'OperationFailed' }) | Should -Be 1
        Resolve-LabExitCode -Result ([pscustomobject]@{ Succeeded = $false; FailureCategory = 'PolicyBlocked' }) | Should -Be 2
        Resolve-LabExitCode -Result ([pscustomobject]@{ Succeeded = $false; FailureCategory = 'ConfigError' }) | Should -Be 3
        Resolve-LabExitCode -Result ([pscustomobject]@{ Succeeded = $false; FailureCategory = 'UnexpectedException' }) | Should -Be 4
    }

    It 'throws a clear error for unsupported commands' {
        { & $launcherPath -Command 'unsupported-command' } | Should -Throw -ExpectedMessage 'Unsupported command: unsupported-command'
    }
}
