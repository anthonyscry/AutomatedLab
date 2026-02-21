BeforeAll {
    # Dot-source the cmdlets under test and their dependencies
    . "$PSScriptRoot/../Private/Save-LabProfile.ps1"
    . "$PSScriptRoot/../Private/Load-LabProfile.ps1"
    . "$PSScriptRoot/../Private/Export-LabPackage.ps1"
    . "$PSScriptRoot/../Private/Import-LabPackage.ps1"

    # Test helper: create a fresh temporary repo root directory
    function New-TestRepoRoot {
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "LabExportImportTest_$(New-Guid)"
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        return $tempPath
    }

    # Test helper: clean up temp repo root
    function Remove-TestRepoRoot {
        param([string]$Path)
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force
        }
    }

    # Test helper: return a realistic $GlobalLabConfig-shaped hashtable
    function New-TestConfig {
        return @{
            Lab     = @{
                Name         = 'TestLab'
                CoreVMNames  = @('DC01', 'SQL01', 'IIS01')
            }
            Network = @{
                SwitchName   = 'LabSwitch'
            }
            Paths   = @{
                LabRoot      = 'C:\Labs\TestLab'
            }
            Credentials = @{
                InstallUser  = 'Administrator'
            }
        }
    }
}

Describe 'Export-LabPackage' {

    It 'exports a saved profile as a package JSON file' {
        $repoRoot = New-TestRepoRoot
        try {
            $null = Save-LabProfile -Name 'export-test' -Config (New-TestConfig) -RepoRoot $repoRoot -Description 'For export'
            $outDir = Join-Path $repoRoot 'packages'
            $null = New-Item -ItemType Directory -Path $outDir -Force

            $result = Export-LabPackage -Name 'export-test' -Path $outDir -RepoRoot $repoRoot

            # Verify output file exists
            Test-Path $result.Path | Should -Be $true

            # Parse and validate package JSON
            $pkg = Get-Content $result.Path -Raw | ConvertFrom-Json
            $pkg.packageVersion | Should -Be '1.0'
            $pkg.sourceName     | Should -Be 'export-test'
            $pkg.exportedAt     | Should -Not -BeNullOrEmpty
            ($pkg | Get-Member -Name 'config' -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws on non-existent profile' {
        $repoRoot = New-TestRepoRoot
        try {
            $outDir = Join-Path $repoRoot 'packages'
            $null = New-Item -ItemType Directory -Path $outDir -Force

            { Export-LabPackage -Name 'no-such-profile' -Path $outDir -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*not found*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws on invalid profile name' {
        $repoRoot = New-TestRepoRoot
        try {
            $outDir = Join-Path $repoRoot 'packages'
            $null = New-Item -ItemType Directory -Path $outDir -Force

            { Export-LabPackage -Name 'bad/name' -Path $outDir -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*invalid characters*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'creates output directory if it does not exist' {
        $repoRoot = New-TestRepoRoot
        try {
            $null = Save-LabProfile -Name 'dir-test' -Config (New-TestConfig) -RepoRoot $repoRoot
            $outDir = Join-Path $repoRoot 'new-packages'
            Test-Path $outDir | Should -Be $false

            $result = Export-LabPackage -Name 'dir-test' -Path $outDir -RepoRoot $repoRoot

            Test-Path $outDir | Should -Be $true
            Test-Path $result.Path | Should -Be $true
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'returns Success object with Path' {
        $repoRoot = New-TestRepoRoot
        try {
            $null = Save-LabProfile -Name 'success-test' -Config (New-TestConfig) -RepoRoot $repoRoot
            $outDir = Join-Path $repoRoot 'packages'
            $null = New-Item -ItemType Directory -Path $outDir -Force

            $result = Export-LabPackage -Name 'success-test' -Path $outDir -RepoRoot $repoRoot

            $result.Success | Should -Be $true
            $result.Path    | Should -Not -BeNullOrEmpty
            Test-Path $result.Path | Should -Be $true
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}

Describe 'Import-LabPackage' {

    It 'imports a valid package as a profile' {
        $repoRoot = New-TestRepoRoot
        try {
            $null = Save-LabProfile -Name 'roundtrip' -Config (New-TestConfig) -RepoRoot $repoRoot
            $outDir = Join-Path $repoRoot 'packages'
            $null = New-Item -ItemType Directory -Path $outDir -Force
            $exportResult = Export-LabPackage -Name 'roundtrip' -Path $outDir -RepoRoot $repoRoot

            $importResult = Import-LabPackage -Path $exportResult.Path -RepoRoot $repoRoot

            $importResult.Success     | Should -Be $true
            $importResult.ProfileName | Should -Be 'roundtrip'

            # Verify profile file exists
            $profilePath = Join-Path (Join-Path (Join-Path $repoRoot '.planning') 'profiles') 'roundtrip.json'
            Test-Path $profilePath | Should -Be $true
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'imports with custom name override' {
        $repoRoot = New-TestRepoRoot
        try {
            $null = Save-LabProfile -Name 'original' -Config (New-TestConfig) -RepoRoot $repoRoot
            $outDir = Join-Path $repoRoot 'packages'
            $null = New-Item -ItemType Directory -Path $outDir -Force
            $exportResult = Export-LabPackage -Name 'original' -Path $outDir -RepoRoot $repoRoot

            $importResult = Import-LabPackage -Path $exportResult.Path -RepoRoot $repoRoot -Name 'custom-name'

            $importResult.ProfileName | Should -Be 'custom-name'

            # Verify the custom-named profile file exists
            $profilePath = Join-Path (Join-Path (Join-Path $repoRoot '.planning') 'profiles') 'custom-name.json'
            Test-Path $profilePath | Should -Be $true
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws on non-existent package file' {
        $repoRoot = New-TestRepoRoot
        try {
            $fakePath = Join-Path $repoRoot 'nonexistent.json'

            { Import-LabPackage -Path $fakePath -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*not found*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'round-trip preserves config data' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig
            $null = Save-LabProfile -Name 'rt-source' -Config $config -RepoRoot $repoRoot
            $outDir = Join-Path $repoRoot 'packages'
            $null = New-Item -ItemType Directory -Path $outDir -Force
            $exportResult = Export-LabPackage -Name 'rt-source' -Path $outDir -RepoRoot $repoRoot

            # Import under a different name
            $null = Import-LabPackage -Path $exportResult.Path -RepoRoot $repoRoot -Name 'rt-imported'

            # Load the imported profile and verify key config values match
            $loaded = Load-LabProfile -Name 'rt-imported' -RepoRoot $repoRoot

            $loaded              | Should -BeOfType [hashtable]
            $loaded.Lab.Name     | Should -Be 'TestLab'
            @($loaded.Lab.CoreVMNames).Count | Should -Be 3
            $loaded.Network.SwitchName | Should -Be 'LabSwitch'
            $loaded.Paths.LabRoot      | Should -Be 'C:\Labs\TestLab'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}

Describe 'Import-LabPackage Validation' {

    It 'rejects package missing packageVersion' {
        $repoRoot = New-TestRepoRoot
        try {
            $pkgDir = Join-Path $repoRoot 'bad-packages'
            $null = New-Item -ItemType Directory -Path $pkgDir -Force
            $pkgPath = Join-Path $pkgDir 'no-version.json'
            @{ sourceName = 'test'; config = @{ Lab = @{ Name = 'X' } } } |
                ConvertTo-Json -Depth 5 | Set-Content $pkgPath -Encoding UTF8

            { Import-LabPackage -Path $pkgPath -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*packageVersion*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'rejects package missing config' {
        $repoRoot = New-TestRepoRoot
        try {
            $pkgDir = Join-Path $repoRoot 'bad-packages'
            $null = New-Item -ItemType Directory -Path $pkgDir -Force
            $pkgPath = Join-Path $pkgDir 'no-config.json'
            @{ packageVersion = '1.0'; sourceName = 'test' } |
                ConvertTo-Json -Depth 5 | Set-Content $pkgPath -Encoding UTF8

            { Import-LabPackage -Path $pkgPath -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*config*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'rejects package missing sourceName' {
        $repoRoot = New-TestRepoRoot
        try {
            $pkgDir = Join-Path $repoRoot 'bad-packages'
            $null = New-Item -ItemType Directory -Path $pkgDir -Force
            $pkgPath = Join-Path $pkgDir 'no-source.json'
            @{ packageVersion = '1.0'; config = @{ Lab = @{ Name = 'X' } } } |
                ConvertTo-Json -Depth 5 | Set-Content $pkgPath -Encoding UTF8

            { Import-LabPackage -Path $pkgPath -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*sourceName*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'rejects package with config missing Lab section' {
        $repoRoot = New-TestRepoRoot
        try {
            $pkgDir = Join-Path $repoRoot 'bad-packages'
            $null = New-Item -ItemType Directory -Path $pkgDir -Force
            $pkgPath = Join-Path $pkgDir 'no-lab.json'
            @{ packageVersion = '1.0'; sourceName = 'test'; config = @{ Network = @{} } } |
                ConvertTo-Json -Depth 5 | Set-Content $pkgPath -Encoding UTF8

            { Import-LabPackage -Path $pkgPath -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*Lab*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'lists ALL validation errors at once' {
        $repoRoot = New-TestRepoRoot
        try {
            $pkgDir = Join-Path $repoRoot 'bad-packages'
            $null = New-Item -ItemType Directory -Path $pkgDir -Force
            $pkgPath = Join-Path $pkgDir 'multi-error.json'
            # Only exportedAt present -- missing packageVersion, sourceName, and config
            '{ "exportedAt": "2026-01-01T00:00:00Z" }' | Set-Content $pkgPath -Encoding UTF8

            try {
                Import-LabPackage -Path $pkgPath -RepoRoot $repoRoot
                throw 'Expected error was not thrown'
            }
            catch {
                $_.Exception.Message | Should -Match 'packageVersion'
                $_.Exception.Message | Should -Match 'sourceName'
                $_.Exception.Message | Should -Match 'config'
            }
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'rejects unparseable JSON' {
        $repoRoot = New-TestRepoRoot
        try {
            $pkgDir = Join-Path $repoRoot 'bad-packages'
            $null = New-Item -ItemType Directory -Path $pkgDir -Force
            $pkgPath = Join-Path $pkgDir 'garbage.json'
            'this is not json {{{{' | Set-Content $pkgPath -Encoding UTF8

            { Import-LabPackage -Path $pkgPath -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*Failed to read*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}
