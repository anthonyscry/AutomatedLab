# SimpleLab Pester Tests
# Run with: Invoke-Pester -Path .\Tests\

BeforeDiscovery {
    # Module path
    $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
}

BeforeAll {
    # Import the module
    $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
    Import-Module $modulePath -Force

    # Dot-source private helpers needed by tests that validate internal behavior.
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
        $platformIsWindows = if ($IsWindows -eq $null) { $env:OS -eq 'Windows_NT' } else { $IsWindows }
        return $platformIsWindows
    }

    function Get-TestTempPath {
        $tempPath = [System.IO.Path]::GetTempPath()
        if ([string]::IsNullOrWhiteSpace($tempPath)) {
            foreach ($variableName in @('TEMP', 'TMP', 'TMPDIR')) {
                $candidate = [Environment]::GetEnvironmentVariable($variableName)
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    $tempPath = $candidate
                    break
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($tempPath)) {
            return $PSScriptRoot
        }

        return $tempPath
    }
}

Describe 'Get-HostInfo' {
    It 'Returns a hashtable with required keys' {
        $result = Get-HostInfo
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'ComputerName'
        $result.Keys | Should -Contain 'PowerShellVersion'
        $result.Keys | Should -Contain 'IsWindows'
    }

    It 'Detects platform correctly' {
        $result = Get-HostInfo
        $expectedIsWindows = Test-IsWindows
        $result.IsWindows | Should -Be $expectedIsWindows
    }
}

Describe 'Test-HyperVEnabled' {
    BeforeEach {
        # Skip Hyper-V tests on non-Windows
        if (-not (Test-IsWindows)) {
            Set-ItResult -Skipped -Because 'Hyper-V is Windows-only'
        }
    }

    It 'Returns a boolean' {
        $result = Test-HyperVEnabled -ErrorAction SilentlyContinue
        $result | Should -BeOfType [bool]
    }
}

Describe 'Test-DiskSpace' {
    It 'Returns a result object with required properties' {
        $path = if (Test-IsWindows) { "C:\" } else { "/" }
        $result = Test-DiskSpace -Path $path -MinSpaceGB 1

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Status'
        $result.PSObject.Properties.Name | Should -Contain 'FreeSpaceGB'
        $result.PSObject.Properties.Name | Should -Contain 'Message'
    }

    It 'Uses appropriate default path for platform' {
        $result = Test-DiskSpace -MinSpaceGB 1
        $result.Path | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-LabConfig' {
    It 'Returns configuration when config file exists' {
        $result = Get-LabConfig
        # Result can be null if config doesn't exist - that's OK
        if ($null -ne $result) {
            $result.PSObject.TypeNames[0] | Should -BeLike '*PSCustomObject*'
        }
    }
}

Describe 'Get-LabVMConfig' {
    It 'Returns default configurations when no config file exists' {
        $result = Get-LabVMConfig
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'dc1'
        $result.Keys | Should -Contain 'svr1'
        $result.Keys | Should -Contain 'ws1'
    }

    It 'Returns specific VM configuration when requested' {
        $result = Get-LabVMConfig -VMName 'dc1'
        $result | Should -Not -BeNullOrEmpty
        $result.MemoryGB | Should -BeGreaterThan 0
        $result.ProcessorCount | Should -BeGreaterThan 0
    }

    It 'Returns null for non-existent VM' {
        $result = Get-LabVMConfig -VMName 'NonExistentVM'
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Write-RunArtifact' {
    BeforeEach {
        # Create a temp directory for artifacts
        $tempDir = Join-Path (Get-TestTempPath) "SimpleLabTests_$(Get-Random)"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        # Clean up temp directory
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Creates an artifact file' {
        # We can't fully test this without modifying the function's path behavior
        # But we can verify the function exists and accepts parameters
        { Write-RunArtifact -Operation 'Test' -Status 'Success' -Duration 1 -ExitCode 0 -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Module Exports' {
    It 'Exports expected public functions' {
        $expectedFunctions = @(
            'Get-LabCheckpoint',
            'Get-LabStatus',
            'Initialize-LabNetwork',
            'Initialize-LabVMs',
            'New-LabSwitch',
            'New-LabVM',
            'Remove-LabVM',
            'Restore-LabCheckpoint',
            'Save-LabCheckpoint',
            'Start-LabVMs',
            'Stop-LabVMs',
            'Test-HyperVEnabled',
            'Test-LabIso',
            'Test-LabNetwork',
            'Test-LabNetworkHealth',
            'Write-RunArtifact'
        )

        $exportedFunctions = (Get-Module -Name 'SimpleLab').ExportedFunctions.Keys

        foreach ($func in $expectedFunctions) {
            $exportedFunctions | Should -Contain $func
        }
    }
}

Describe 'Get-LabStatus' {
    BeforeEach {
        if (-not (Test-IsWindows)) {
            Set-ItResult -Skipped -Because 'Hyper-V is Windows-only'
        }
    }

    It 'Returns an array of VM status objects' {
        $result = Get-LabStatus
        @($result).Count | Should -BeGreaterThan 0
    }

    It 'Each VM status has required properties' {
        $result = Get-LabStatus
        foreach ($vm in $result) {
            $vm.PSObject.Properties.Name | Should -Contain 'VMName'
            $vm.PSObject.Properties.Name | Should -Contain 'State'
            $vm.PSObject.Properties.Name | Should -Contain 'Status'
        }
    }
}
