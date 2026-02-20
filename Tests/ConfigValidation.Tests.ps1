BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabHostResourceInfo.ps1')
    . (Join-Path $repoRoot 'Private/Test-LabConfigValidation.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabScenarioResourceEstimate.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabScenarioTemplate.ps1')
    . (Join-Path $repoRoot 'Private/Test-LabTemplateData.ps1')

    # Stub Get-WindowsOptionalFeature on non-Windows so Pester can mock it
    if (-not (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
        function global:Get-WindowsOptionalFeature {
            param([switch]$Online, [string]$FeatureName)
            throw 'Get-WindowsOptionalFeature is not available on this platform'
        }
    }
}

Describe 'Get-LabHostResourceInfo' {

    It 'Returns a PSCustomObject' {
        $result = Get-LabHostResourceInfo
        $result | Should -BeOfType [PSCustomObject]
    }

    It 'Has FreeRAMGB property' {
        $result = Get-LabHostResourceInfo
        $result.PSObject.Properties.Name | Should -Contain 'FreeRAMGB'
    }

    It 'Has FreeDiskGB property' {
        $result = Get-LabHostResourceInfo
        $result.PSObject.Properties.Name | Should -Contain 'FreeDiskGB'
    }

    It 'Has LogicalProcessors property' {
        $result = Get-LabHostResourceInfo
        $result.PSObject.Properties.Name | Should -Contain 'LogicalProcessors'
    }

    It 'Has DiskPath property' {
        $result = Get-LabHostResourceInfo
        $result.PSObject.Properties.Name | Should -Contain 'DiskPath'
    }

    It 'FreeRAMGB is a positive number' {
        $result = Get-LabHostResourceInfo
        $result.FreeRAMGB | Should -BeGreaterThan 0
    }

    It 'FreeDiskGB is a positive number' {
        $result = Get-LabHostResourceInfo
        $result.FreeDiskGB | Should -BeGreaterThan 0
    }

    It 'LogicalProcessors is a positive integer' {
        $result = Get-LabHostResourceInfo
        $result.LogicalProcessors | Should -BeGreaterThan 0
        $result.LogicalProcessors | Should -BeOfType [int]
    }

    It 'Accepts -DiskPath parameter without error' {
        # Use the default path for current platform
        $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
        $platformIsWindows = if ($null -eq $isWindowsVar) { $env:OS -eq 'Windows_NT' } else { $isWindowsVar.Value }
        $testPath = if ($platformIsWindows) { 'C:\' } else { '/' }

        { Get-LabHostResourceInfo -DiskPath $testPath } | Should -Not -Throw
    }

    It 'Throws with prefix on invalid disk path' {
        # Mock Get-PSDrive to simulate invalid drive
        Mock Get-PSDrive { return $null } -ParameterFilter { $Name -eq 'Z' }

        $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
        $platformIsWindows = if ($null -eq $isWindowsVar) { $env:OS -eq 'Windows_NT' } else { $isWindowsVar.Value }

        if ($platformIsWindows) {
            { Get-LabHostResourceInfo -DiskPath 'Z:\' } | Should -Throw '*Get-LabHostResourceInfo:*'
        }
        else {
            { Get-LabHostResourceInfo -DiskPath '/nonexistent/path/that/does/not/exist' } | Should -Throw '*Get-LabHostResourceInfo:*'
        }
    }
}

Describe 'Test-LabConfigValidation' {

    BeforeEach {
        # Mock Get-LabHostResourceInfo with consistent values
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 32.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        # Mock Get-LabScenarioResourceEstimate
        Mock Get-LabScenarioResourceEstimate {
            return [pscustomobject]@{
                Scenario        = 'TestScenario'
                VMCount         = 2
                TotalRAMGB      = 8
                TotalDiskGB     = 160
                TotalProcessors = 4
                VMs             = @()
            }
        }

        # Mock Get-WindowsOptionalFeature to return enabled
        Mock Get-WindowsOptionalFeature {
            return [pscustomobject]@{ State = 'Enabled' }
        }

        # Set GlobalLabConfig in test scope
        $script:GlobalLabConfig = @{
            Lab         = @{ Name = 'TestLab'; DomainName = 'test.local' }
            Network     = @{ SwitchName = 'TestSwitch' }
            Credentials = @{ InstallUser = 'admin'; AdminPassword = 'Test123!' }
            VMSizing    = @{ DC = @{ Memory = 4GB; Processors = 4 } }
        }
    }

    It 'Returns PSCustomObject with OverallStatus property' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'Returns PSCustomObject with Checks property' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.PSObject.Properties.Name | Should -Contain 'Checks'
    }

    It 'Returns PSCustomObject with Summary property' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.PSObject.Properties.Name | Should -Contain 'Summary'
    }

    It 'OverallStatus is Pass when all checks pass' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.OverallStatus | Should -Be 'Pass'
    }

    It 'Returns 5 checks' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.Checks.Count | Should -Be 5
    }

    It 'Each check has Name, Status, Message, Remediation properties' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        foreach ($check in $result.Checks) {
            $check.PSObject.Properties.Name | Should -Contain 'Name'
            $check.PSObject.Properties.Name | Should -Contain 'Status'
            $check.PSObject.Properties.Name | Should -Contain 'Message'
            $check.PSObject.Properties.Name | Should -Contain 'Remediation'
        }
    }

    It 'RAM check fails when free RAM is less than scenario requirement' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 2.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $ramCheck = $result.Checks | Where-Object { $_.Name -eq 'RAM' }
        $ramCheck.Status | Should -Be 'Fail'
    }

    It 'RAM failure includes remediation mentioning required and available amounts' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 2.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $ramCheck = $result.Checks | Where-Object { $_.Name -eq 'RAM' }
        $ramCheck.Remediation | Should -Not -BeNullOrEmpty
        $ramCheck.Remediation | Should -BeLike '*8*'
        $ramCheck.Remediation | Should -BeLike '*2*'
    }

    It 'Disk check fails when free disk is less than scenario requirement' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 32.0
                FreeDiskGB        = 50.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $diskCheck = $result.Checks | Where-Object { $_.Name -eq 'Disk' }
        $diskCheck.Status | Should -Be 'Fail'
    }

    It 'Disk failure includes remediation mentioning disk space' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 32.0
                FreeDiskGB        = 50.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $diskCheck = $result.Checks | Where-Object { $_.Name -eq 'Disk' }
        $diskCheck.Remediation | Should -Not -BeNullOrEmpty
        $diskCheck.Remediation | Should -BeLike '*disk*'
    }

    It 'CPU check warns (not fails) when host CPUs are less than scenario total' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 32.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 2
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $cpuCheck = $result.Checks | Where-Object { $_.Name -eq 'CPU' }
        $cpuCheck.Status | Should -Be 'Warn'
        $cpuCheck.Status | Should -Not -Be 'Fail'
    }

    It 'CPU warning message mentions available and requested counts' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 32.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 2
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $cpuCheck = $result.Checks | Where-Object { $_.Name -eq 'CPU' }
        $cpuCheck.Message | Should -BeLike '*2*'
        $cpuCheck.Message | Should -BeLike '*4*'
        $cpuCheck.Message | Should -BeLike '*VMs will share CPU time*'
    }

    It 'Config check fails when GlobalLabConfig is missing required sections' {
        $script:GlobalLabConfig = @{}

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $configCheck = $result.Checks | Where-Object { $_.Name -eq 'Config' }
        $configCheck.Status | Should -Be 'Fail'
    }

    It 'Config failure remediation mentions Lab-Config.ps1' {
        $script:GlobalLabConfig = @{}

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $configCheck = $result.Checks | Where-Object { $_.Name -eq 'Config' }
        $configCheck.Remediation | Should -BeLike '*Lab-Config.ps1*'
    }

    It 'Without -Scenario parameter, RAM/Disk/CPU checks pass with no-scenario message' {
        $result = Test-LabConfigValidation
        $ramCheck = $result.Checks | Where-Object { $_.Name -eq 'RAM' }
        $diskCheck = $result.Checks | Where-Object { $_.Name -eq 'Disk' }
        $cpuCheck = $result.Checks | Where-Object { $_.Name -eq 'CPU' }

        $ramCheck.Status | Should -Be 'Pass'
        $diskCheck.Status | Should -Be 'Pass'
        $cpuCheck.Status | Should -Be 'Pass'
        $ramCheck.Message | Should -BeLike '*No scenario specified*'
        $diskCheck.Message | Should -BeLike '*No scenario specified*'
        $cpuCheck.Message | Should -BeLike '*No scenario specified*'
    }

    It 'Summary string contains pass/fail/warn counts' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.Summary | Should -BeLike '*passed*'
        $result.Summary | Should -BeLike '*failed*'
        $result.Summary | Should -BeLike '*warning*'
    }

    It 'OverallStatus is Fail if any single check fails' {
        # Force RAM failure
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 2.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.OverallStatus | Should -Be 'Fail'
    }

    It 'Hyper-V check handles non-Windows with Warn status' {
        Mock Get-WindowsOptionalFeature { throw 'Not available' }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $hyperVCheck = $result.Checks | Where-Object { $_.Name -eq 'HyperV' }
        $hyperVCheck.Status | Should -Be 'Warn'
        $hyperVCheck.Status | Should -Not -Be 'Fail'
    }

    It 'Hyper-V Warn message mentions Windows' {
        Mock Get-WindowsOptionalFeature { throw 'Not available' }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $hyperVCheck = $result.Checks | Where-Object { $_.Name -eq 'HyperV' }
        $hyperVCheck.Message | Should -BeLike '*Windows*'
    }

    It 'OverallStatus is Pass when only warnings exist (no failures)' {
        # CPU warning + HyperV warning, but no failures
        Mock Get-WindowsOptionalFeature { throw 'Not available' }
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 32.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 2
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.OverallStatus | Should -Be 'Pass'
    }

    It 'Check names include HyperV, RAM, Disk, CPU, Config' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $checkNames = $result.Checks | ForEach-Object { $_.Name }
        $checkNames | Should -Contain 'HyperV'
        $checkNames | Should -Contain 'RAM'
        $checkNames | Should -Contain 'Disk'
        $checkNames | Should -Contain 'CPU'
        $checkNames | Should -Contain 'Config'
    }

    It 'Passed checks have null Remediation' {
        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $passedChecks = $result.Checks | Where-Object { $_.Status -eq 'Pass' }
        foreach ($check in $passedChecks) {
            $check.Remediation | Should -BeNullOrEmpty
        }
    }

    It 'Failed checks have non-null Remediation' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 2.0
                FreeDiskGB        = 50.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $failedChecks = $result.Checks | Where-Object { $_.Status -eq 'Fail' }
        $failedChecks.Count | Should -BeGreaterThan 0
        foreach ($check in $failedChecks) {
            $check.Remediation | Should -Not -BeNullOrEmpty
        }
    }

    It 'Multiple failures result in Fail overall status' {
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 2.0
                FreeDiskGB        = 50.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }
        $script:GlobalLabConfig = @{}

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $result.OverallStatus | Should -Be 'Fail'
        $failedChecks = $result.Checks | Where-Object { $_.Status -eq 'Fail' }
        $failedChecks.Count | Should -BeGreaterOrEqual 3
    }

    It 'RAM/Disk/CPU warn when scenario command not available' {
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'Get-LabScenarioResourceEstimate' }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $ramCheck = $result.Checks | Where-Object { $_.Name -eq 'RAM' }
        $diskCheck = $result.Checks | Where-Object { $_.Name -eq 'Disk' }
        $cpuCheck = $result.Checks | Where-Object { $_.Name -eq 'CPU' }

        $ramCheck.Status | Should -Be 'Warn'
        $diskCheck.Status | Should -Be 'Warn'
        $cpuCheck.Status | Should -Be 'Warn'
        $ramCheck.Message | Should -BeLike '*not available*'
    }

    It 'Config check detects missing Lab section' {
        $script:GlobalLabConfig = @{
            Network     = @{ SwitchName = 'TestSwitch' }
            Credentials = @{ InstallUser = 'admin' }
            VMSizing    = @{ DC = @{ Memory = 4GB } }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        $configCheck = $result.Checks | Where-Object { $_.Name -eq 'Config' }
        $configCheck.Status | Should -Be 'Fail'
        $configCheck.Message | Should -BeLike '*Lab*'
    }

    It 'Summary counts match actual check statuses' {
        Mock Get-WindowsOptionalFeature { throw 'Not available' }
        Mock Get-LabHostResourceInfo {
            return [pscustomobject]@{
                FreeRAMGB         = 2.0
                FreeDiskGB        = 500.0
                LogicalProcessors = 8
                DiskPath          = 'C:\'
            }
        }

        $result = Test-LabConfigValidation -Scenario 'TestScenario'
        # Should have: HyperV=Warn, RAM=Fail, Disk=Pass, CPU=Pass, Config=Pass
        $result.Summary | Should -BeLike '*3 passed*'
        $result.Summary | Should -BeLike '*1 failed*'
        $result.Summary | Should -BeLike '*1 warning*'
    }
}
