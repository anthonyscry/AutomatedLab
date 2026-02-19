Describe 'Get-LabCommandMap' {
    BeforeAll {
        $moduleManifestPath = Join-Path -Path (Get-Location) -ChildPath 'OpenCodeLab-v2/src/OpenCodeLab.App/OpenCodeLab.App.psd1'
        Import-Module $moduleManifestPath -Force
    }

    It 'exposes the required command keys' {
        $commandMap = Get-LabCommandMap
        $expectedKeys = @('preflight', 'deploy', 'teardown', 'status', 'health', 'dashboard')

        $commandMap | Should -Not -BeNullOrEmpty
        $commandMap.Keys.Count | Should -Be $expectedKeys.Count

        foreach ($key in $expectedKeys) {
            $commandMap.Keys | Should -Contain $key
        }
    }
}
