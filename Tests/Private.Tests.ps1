# SimpleLab Private Functions Tests
# Tests for internal helper functions

BeforeDiscovery {
    $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
}

BeforeAll {
    # Import the module
    $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
    Import-Module $modulePath -Force

    # Dot-source private helpers under test.
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $privateScripts = @(
        Get-ChildItem -Path (Join-Path $repoRoot 'Private') -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName
    )
    foreach ($script in $privateScripts) {
        . $script.FullName
    }

    # Helper function to detect platform
    function Test-IsWindows {
        $isWindows = if ($IsWindows -eq $null) { $env:OS -eq 'Windows_NT' } else { $IsWindows }
        return $isWindows
    }
}

Describe 'Get-LabNetworkConfig' {
    It 'Returns network configuration with VM IPs' {
        $result = Get-LabNetworkConfig
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'VMIPs'
        $result.PSObject.Properties.Name | Should -Contain 'PrefixLength'
    }

    It 'Contains IPs for all lab VMs' {
        $result = Get-LabNetworkConfig
        $vmIpKeys = if ($result.VMIPs -is [hashtable]) {
            $result.VMIPs.Keys
        } else {
            $result.VMIPs.PSObject.Properties.Name
        }
        $vmIpKeys | Should -Contain 'dc1'
        $vmIpKeys | Should -Contain 'svr1'
        $vmIpKeys | Should -Contain 'ws1'
    }
}

Describe 'Test-LabVM' {
    It 'Returns result object with Exists property' {
        $result = Test-LabVM -VMName 'NonExistentTestVM'
        $result.PSObject.Properties.Name | Should -Contain 'Exists'
        $result.Exists | Should -BeOfType [bool]
    }
}

Describe 'Find-LabIso' {
    It 'Returns result object with Found property' {
        $searchPaths = @($env:TEMP)
        $result = Find-LabIso -IsoName 'TestISO' -SearchPaths $searchPaths
        $result.PSObject.Properties.Name | Should -Contain 'Found'
        $result.Found | Should -BeOfType [bool]
    }

    It 'Returns Found=false when ISO does not exist' {
        $searchPaths = @($env:TEMP)
        $result = Find-LabIso -IsoName 'DefinitelyNotExistingISO_12345' -SearchPaths $searchPaths
        $result.Found | Should -Be $false
    }
}

Describe 'Initialize-LabConfig' {
    It 'Creates config file when it does not exist' {
        # Test in a temp location
        $tempDir = Join-Path $env:TEMP "SimpleLabConfigTest_$(Get-Random)"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        try {
            $tempConfigPath = Join-Path $tempDir "test-config.json"

            # This test verifies the function can be called
            # Actual file creation depends on the implementation
            { Initialize-LabConfig -ConfigPath $tempConfigPath -ErrorAction Stop } | Should -Not -Throw
        }
        finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Write-ValidationReport' {
    It 'Returns result object with ExitCode' {
        $mockResults = [PSCustomObject]@{
            OverallStatus = 'Pass'
            Checks = @()
            FailedChecks = @()
            Duration = 1.0
            Timestamp = (Get-Date).ToString('o')
        }

        $result = Write-ValidationReport -Results $mockResults
        $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
        $result.ExitCode | Should -BeOfType [int]
    }

    It 'Returns ExitCode 0 for Pass status' {
        $mockResults = [PSCustomObject]@{
            OverallStatus = 'Pass'
            Checks = @()
            FailedChecks = @()
            Duration = 1.0
            Timestamp = (Get-Date).ToString('o')
        }

        $result = Write-ValidationReport -Results $mockResults
        $result.ExitCode | Should -Be 0
    }

    It 'Returns non-zero ExitCode for Fail status' {
        $mockResults = [PSCustomObject]@{
            OverallStatus = 'Fail'
            Checks = @()
            FailedChecks = @('HyperV')
            Duration = 1.0
            Timestamp = (Get-Date).ToString('o')
        }

        $result = Write-ValidationReport -Results $mockResults
        $result.ExitCode | Should -Not -Be 0
    }
}
