BeforeAll {
    # Dot-source all four profile cmdlets
    . "$PSScriptRoot/../Private/Save-LabProfile.ps1"
    . "$PSScriptRoot/../Private/Get-LabProfile.ps1"
    . "$PSScriptRoot/../Private/Remove-LabProfile.ps1"
    . "$PSScriptRoot/../Private/Load-LabProfile.ps1"

    # Test helper: create a fresh temporary repo root directory
    function New-TestRepoRoot {
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "LabProfileTest_$(New-Guid)"
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

Describe 'Save-LabProfile' {

    It 'throws on invalid profile name with special characters' {
        $repoRoot = New-TestRepoRoot
        try {
            { Save-LabProfile -Name 'bad@name!' -Config (New-TestConfig) -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*contains invalid characters*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'saves a profile successfully with correct metadata' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig
            $result = Save-LabProfile -Name 'myprofile' -Config $config -RepoRoot $repoRoot -Description 'A test profile'

            $result.Success | Should -Be $true
            $result.Message | Should -Match 'saved successfully'

            # Verify file was created
            $profilePath = Join-Path (Join-Path (Join-Path $repoRoot '.planning') 'profiles') 'myprofile.json'
            Test-Path $profilePath | Should -Be $true

            # Verify JSON content
            $data = Get-Content $profilePath -Raw | ConvertFrom-Json
            $data.name      | Should -Be 'myprofile'
            $data.createdAt | Should -Not -BeNullOrEmpty
            $data.vmCount   | Should -Be 3
            ($data | Get-Member -Name 'config' -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'overwrites existing profile without error' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig
            $null = Save-LabProfile -Name 'overwrite' -Config $config -RepoRoot $repoRoot -Description 'First save'

            # Second save with different description
            $result = Save-LabProfile -Name 'overwrite' -Config $config -RepoRoot $repoRoot -Description 'Second save'
            $result.Success | Should -Be $true

            $profilePath = Join-Path (Join-Path (Join-Path $repoRoot '.planning') 'profiles') 'overwrite.json'
            $data = Get-Content $profilePath -Raw | ConvertFrom-Json
            $data.description | Should -Be 'Second save'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'creates profiles directory if it does not exist' {
        $repoRoot = New-TestRepoRoot
        try {
            # Confirm profiles dir does NOT exist yet
            $profilesDir = Join-Path (Join-Path $repoRoot '.planning') 'profiles'
            Test-Path $profilesDir | Should -Be $false

            $null = Save-LabProfile -Name 'newdir' -Config (New-TestConfig) -RepoRoot $repoRoot

            # Confirm directory and file were created
            Test-Path $profilesDir | Should -Be $true
            $profilePath = Join-Path $profilesDir 'newdir.json'
            Test-Path $profilePath | Should -Be $true
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}

Describe 'Get-LabProfile' {

    It 'returns empty array when no profiles exist' {
        $repoRoot = New-TestRepoRoot
        try {
            $result = Get-LabProfile -RepoRoot $repoRoot
            @($result).Count | Should -Be 0
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'returns summary for all saved profiles' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig
            $null = Save-LabProfile -Name 'profile-a' -Config $config -RepoRoot $repoRoot
            Start-Sleep -Milliseconds 10
            $null = Save-LabProfile -Name 'profile-b' -Config $config -RepoRoot $repoRoot

            $result = @(Get-LabProfile -RepoRoot $repoRoot)
            $result.Count | Should -Be 2

            # Each summary should have the expected properties
            foreach ($p in $result) {
                $p.Name      | Should -Not -BeNullOrEmpty
                $p.VMCount   | Should -Be 3
                $p.CreatedAt | Should -Not -BeNullOrEmpty
            }
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'retrieves a single profile by name' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig
            $null = Save-LabProfile -Name 'single' -Config $config -RepoRoot $repoRoot -Description 'Single profile'

            $result = Get-LabProfile -RepoRoot $repoRoot -Name 'single'
            $result | Should -Not -BeNullOrEmpty
            $result.name        | Should -Be 'single'
            $result.description | Should -Be 'Single profile'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws when named profile does not exist' {
        $repoRoot = New-TestRepoRoot
        try {
            { Get-LabProfile -RepoRoot $repoRoot -Name 'nonexistent' } |
                Should -Throw -ExpectedMessage "*not found*"
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}

Describe 'Remove-LabProfile' {

    It 'removes an existing profile' {
        $repoRoot = New-TestRepoRoot
        try {
            $null = Save-LabProfile -Name 'todelete' -Config (New-TestConfig) -RepoRoot $repoRoot
            $profilePath = Join-Path (Join-Path (Join-Path $repoRoot '.planning') 'profiles') 'todelete.json'
            Test-Path $profilePath | Should -Be $true

            $result = Remove-LabProfile -Name 'todelete' -RepoRoot $repoRoot
            $result.Success | Should -Be $true
            Test-Path $profilePath | Should -Be $false
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws when profile does not exist' {
        $repoRoot = New-TestRepoRoot
        try {
            { Remove-LabProfile -Name 'ghost' -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage "*not found*"
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws on invalid name characters' {
        $repoRoot = New-TestRepoRoot
        try {
            { Remove-LabProfile -Name '../escape' -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage '*contains invalid characters*'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}

Describe 'Load-LabProfile' {

    It 'loads a saved profile and returns a hashtable' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig
            $null = Save-LabProfile -Name 'loadme' -Config $config -RepoRoot $repoRoot

            $result = Load-LabProfile -Name 'loadme' -RepoRoot $repoRoot

            $result            | Should -BeOfType [hashtable]
            $result.Lab.Name   | Should -Be 'TestLab'
            $result.Network.SwitchName | Should -Be 'LabSwitch'
            $result.Paths.LabRoot      | Should -Be 'C:\Labs\TestLab'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws when profile does not exist' {
        $repoRoot = New-TestRepoRoot
        try {
            { Load-LabProfile -Name 'missing' -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage "*not found*"
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'throws on malformed profile missing config key' {
        $repoRoot = New-TestRepoRoot
        try {
            # Manually write a JSON file without a 'config' property
            $profilesDir = Join-Path (Join-Path $repoRoot '.planning') 'profiles'
            New-Item -ItemType Directory -Path $profilesDir -Force | Out-Null
            $malformedPath = Join-Path $profilesDir 'malformed.json'
            '{ "name": "malformed", "createdAt": "2026-01-01T00:00:00Z" }' | Set-Content $malformedPath -Encoding UTF8

            { Load-LabProfile -Name 'malformed' -RepoRoot $repoRoot } |
                Should -Throw -ExpectedMessage "*malformed*missing 'config' key*"
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }

    It 'preserves array values through round-trip' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig
            $null = Save-LabProfile -Name 'arrayroundtrip' -Config $config -RepoRoot $repoRoot

            $result = Load-LabProfile -Name 'arrayroundtrip' -RepoRoot $repoRoot

            # CoreVMNames array should survive the JSON round-trip
            $vmNames = @($result.Lab.CoreVMNames)
            $vmNames.Count  | Should -Be 3
            $vmNames[0]     | Should -Be 'DC01'
            $vmNames[1]     | Should -Be 'SQL01'
            $vmNames[2]     | Should -Be 'IIS01'
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}

Describe 'Profile CRUD Integration' {

    It 'completes full save-list-load-remove lifecycle' {
        $repoRoot = New-TestRepoRoot
        try {
            $config = New-TestConfig

            # Save
            $saveResult = Save-LabProfile -Name 'lifecycle' -Config $config -RepoRoot $repoRoot -Description 'Integration test'
            $saveResult.Success | Should -Be $true

            # List -- expect exactly 1 profile
            $listing = @(Get-LabProfile -RepoRoot $repoRoot)
            $listing.Count    | Should -Be 1
            $listing[0].Name  | Should -Be 'lifecycle'

            # Load -- verify config round-trips correctly
            $loaded = Load-LabProfile -Name 'lifecycle' -RepoRoot $repoRoot
            $loaded               | Should -BeOfType [hashtable]
            $loaded.Lab.Name      | Should -Be 'TestLab'
            @($loaded.Lab.CoreVMNames).Count | Should -Be 3

            # Remove
            $removeResult = Remove-LabProfile -Name 'lifecycle' -RepoRoot $repoRoot
            $removeResult.Success | Should -Be $true

            # List again -- expect 0 profiles
            $emptyListing = @(Get-LabProfile -RepoRoot $repoRoot)
            $emptyListing.Count | Should -Be 0
        }
        finally {
            Remove-TestRepoRoot $repoRoot
        }
    }
}
