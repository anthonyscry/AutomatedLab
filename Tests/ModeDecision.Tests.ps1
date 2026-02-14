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
}
