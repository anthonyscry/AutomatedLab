# Invoke-LabQuickModeHeal tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Invoke-LabQuickModeHeal.ps1')
}

Describe 'Invoke-LabQuickModeHeal' {
    BeforeEach {
        $script:switchCalled = $false
        $script:natCalled = $false

        function New-LabSwitch { $script:switchCalled = $true }
        function New-LabNAT { $script:natCalled = $true }
        function Save-LabReadyCheckpoint { }
        function Start-LabVMs { }
        function Wait-LabVMReady { return $true }
        function Test-LabDomainHealth { return $true }
    }

    It 'returns no-op when probe is clean' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeFalse
        $result.HealSucceeded | Should -BeFalse
        $result.RepairsApplied | Should -HaveCount 0
        $result.RemainingIssues | Should -HaveCount 0
    }

    It 'skips heal when lab not registered' {
        $probe = [pscustomobject]@{
            LabRegistered = $false
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $false
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeFalse
    }

    It 'skips heal when VMs are missing' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @('svr1')
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeFalse
    }

    It 'heals missing switch' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $false
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -Contain 'switch_recreated'
        $script:switchCalled | Should -BeTrue
    }

    It 'heals missing NAT' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -Contain 'nat_recreated'
        $script:natCalled | Should -BeTrue
    }

    It 'heals both switch and NAT in one pass' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $false
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -HaveCount 2
        $result.RepairsApplied | Should -Contain 'switch_recreated'
        $result.RepairsApplied | Should -Contain 'nat_recreated'
    }

    It 'skips heal when disabled via config' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $false
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24' -Enabled:$false

        $result.HealAttempted | Should -BeFalse
    }

    It 'reports remaining issues when switch repair throws' {
        function New-LabSwitch { throw 'Access denied' }

        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $false
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeFalse
        $result.RemainingIssues | Should -Contain 'switch_repair_failed'
    }

    It 'heals missing LabReady when VMs are healthy' {
        $script:snapshotCalled = $false
        function Save-LabReadyCheckpoint { $script:snapshotCalled = $true }

        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24' -VMNames @('dc1', 'svr1', 'ws1')

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -Contain 'labready_created'
        $script:snapshotCalled | Should -BeTrue
    }

    It 'refuses LabReady when VM health check fails' {
        function Test-LabDomainHealth { return $false }

        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24' -VMNames @('dc1', 'svr1', 'ws1')

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeFalse
        $result.RemainingIssues | Should -Contain 'labready_unhealable'
    }

    It 'skips LabReady heal when no VMNames provided' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeFalse
        $result.RemainingIssues | Should -Contain 'labready_unhealable'
    }
}
