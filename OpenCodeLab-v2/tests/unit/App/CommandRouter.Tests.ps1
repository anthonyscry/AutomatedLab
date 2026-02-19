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
            preflight = 'Invoke-LabPreflight'
            deploy    = 'Invoke-LabDeploy'
            teardown  = 'Invoke-LabTeardown'
            status    = 'Get-LabStatus'
            health    = 'Get-LabHealth'
            dashboard = 'Start-LabDashboard'
        }

        $commandMap | Should -Not -BeNullOrEmpty
        $commandMap.Keys.Count | Should -Be $expectedMap.Keys.Count

        foreach ($key in $expectedMap.Keys) {
            $commandMap.Keys | Should -Contain $key
            $commandMap[$key] | Should -Be $expectedMap[$key]
        }
    }

    It 'resolves launcher commands using the command map' {
        $commandMap = Get-LabCommandMap

        foreach ($command in $commandMap.Keys) {
            & $launcherPath -Command $command | Should -Be $commandMap[$command]
        }
    }

    It 'throws a clear error for unsupported commands' {
        { & $launcherPath -Command 'unsupported-command' } | Should -Throw -ExpectedMessage 'Unsupported command: unsupported-command'
    }
}
