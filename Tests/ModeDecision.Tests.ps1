# Resolve-LabModeDecision and Get-LabStateProbe tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabModeDecision.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabStateProbe.ps1')
}

Describe 'Resolve-LabModeDecision' {
    It 'quick deploy stays quick when state reusable' {
        $state = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $state

        $result.RequestedMode | Should -Be 'quick'
        $result.EffectiveMode | Should -Be 'quick'
        $result.FallbackReason | Should -BeNullOrEmpty
    }

    It 'quick deploy escalates for missing LabReady' {
        $state = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $state

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'missing_labready'
    }

    It 'quick deploy escalates for missing VMs' {
        $state = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @('ws1')
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $state

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'vm_state_inconsistent'
    }

    It 'quick deploy escalates for lab not registered' {
        $state = [pscustomobject]@{
            LabRegistered = $false
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $state

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'lab_not_registered'
    }

    It 'quick deploy escalates for infra drift' {
        $state = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $false
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $state

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'infra_drift_detected'
    }

    It 'full mode remains full' {
        $state = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode full -State $state

        $result.RequestedMode | Should -Be 'full'
        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -BeNullOrEmpty
    }

    It 'quick deploy does not trust JSON-like and arbitrary string values for booleans' {
        $state = [pscustomobject]@{
            LabRegistered = '{"value":false}'
            MissingVMs = @()
            LabReadyAvailable = '[]'
            SwitchPresent = 'false'
            NatPresent = 'off'
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $state

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'lab_not_registered'
    }

    It 'quick deploy treats explicit false string values as false' {
        $state = [pscustomobject]@{
            LabRegistered = 'true'
            MissingVMs = @()
            LabReadyAvailable = 'false'
            SwitchPresent = 'true'
            NatPresent = 'true'
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $state

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'missing_labready'
    }

    It 'quick teardown stays quick regardless of probe state' {
        $state = [pscustomobject]@{
            LabRegistered = $false
            MissingVMs = @('dc1')
            LabReadyAvailable = $false
            SwitchPresent = $false
            NatPresent = $false
        }

        $result = Resolve-LabModeDecision -Operation teardown -RequestedMode quick -State $state

        $result.RequestedMode | Should -Be 'quick'
        $result.EffectiveMode | Should -Be 'quick'
        $result.FallbackReason | Should -BeNullOrEmpty
    }
}

Describe 'Get-LabStateProbe' {
    It 'returns expected shape and conservative defaults when cmdlets are unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -in @('Get-Lab', 'Get-VM', 'Get-VMSnapshot', 'Get-VMSwitch', 'Get-NetNat') }

        $result = Get-LabStateProbe -LabName 'TestLab' -VMNames @('dc1', 'ws1') -SwitchName 'LabSwitch' -NatName 'LabNat'

        $result.PSObject.Properties.Name | Should -Contain 'LabRegistered'
        $result.PSObject.Properties.Name | Should -Contain 'MissingVMs'
        $result.PSObject.Properties.Name | Should -Contain 'LabReadyAvailable'
        $result.PSObject.Properties.Name | Should -Contain 'SwitchPresent'
        $result.PSObject.Properties.Name | Should -Contain 'NatPresent'

        $result.LabRegistered | Should -BeFalse
        $result.MissingVMs | Should -Be @('dc1', 'ws1')
        $result.LabReadyAvailable | Should -BeFalse
        $result.SwitchPresent | Should -BeFalse
        $result.NatPresent | Should -BeFalse
    }

    It 'uses probe cmdlets when available and reports reusable state' {
        function Get-Lab { param([string]$Name) [pscustomobject]@{ Name = $Name } }
        function Get-VM { param([string]$Name) [pscustomobject]@{ Name = $Name } }
        function Get-VMSnapshot { param([string]$VMName, [string]$Name) [pscustomobject]@{ VMName = $VMName; Name = $Name } }
        function Get-VMSwitch { param([string]$Name) [pscustomobject]@{ Name = $Name } }
        function Get-NetNat { param([string]$Name) [pscustomobject]@{ Name = $Name } }

        $result = Get-LabStateProbe -LabName 'TestLab' -VMNames @('dc1', 'ws1') -SwitchName 'LabSwitch' -NatName 'LabNat'

        $result.LabRegistered | Should -BeTrue
        $result.MissingVMs | Should -Be @()
        $result.LabReadyAvailable | Should -BeTrue
        $result.SwitchPresent | Should -BeTrue
        $result.NatPresent | Should -BeTrue

        Remove-Item Function:\Get-Lab
        Remove-Item Function:\Get-VM
        Remove-Item Function:\Get-VMSnapshot
        Remove-Item Function:\Get-VMSwitch
        Remove-Item Function:\Get-NetNat
    }
}
