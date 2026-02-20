# NetworkInfra.Tests.ps1 -- Unit tests for network infrastructure Public functions
# Covers: New-LabSwitch, Remove-LabSwitch, New-LabNAT, Initialize-LabNetwork,
#          Test-LabNetwork, Test-LabNetworkHealth

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    . (Join-Path $script:repoRoot 'Public' 'New-LabSwitch.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Remove-LabSwitch.ps1')
    . (Join-Path $script:repoRoot 'Public' 'New-LabNAT.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Initialize-LabNetwork.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Test-LabNetwork.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Test-LabNetworkHealth.ps1')

    # Stub dependencies
    if (-not (Get-Command Write-LabStatus -ErrorAction SilentlyContinue)) {
        function Write-LabStatus { param($Status, $Message, $Indent) }
    }
    if (-not (Get-Command Get-LabVMConfig -ErrorAction SilentlyContinue)) {
        function Get-LabVMConfig { @{ dc1 = @{ Name = 'dc1' } } }
    }
}

Describe 'New-LabSwitch' {
    BeforeEach {
        Register-HyperVMocks
        # Test-LabNetwork is called inside New-LabSwitch
        if (-not (Get-Command Test-LabNetwork -ErrorAction SilentlyContinue)) {
            # Already loaded above
        }
        Mock Test-LabNetwork { [PSCustomObject]@{ Exists = $false; SwitchName = 'SimpleLab'; SwitchType = '' } }
    }

    It 'creates switch and returns OK status' {
        $result = New-LabSwitch
        $result.Status | Should -Be 'OK'
        $result.Created | Should -BeTrue
        $result.SwitchName | Should -Be 'SimpleLab'
        Should -Invoke New-VMSwitch -Times 1 -Exactly
    }

    It 'returns OK without creating when switch already exists' {
        Mock Test-LabNetwork { [PSCustomObject]@{ Exists = $true; SwitchName = 'SimpleLab'; SwitchType = 'Internal' } }
        $result = New-LabSwitch
        $result.Status | Should -Be 'OK'
        $result.Created | Should -BeFalse
        Should -Invoke New-VMSwitch -Times 0 -Exactly
    }

    It 'recreates switch when Force specified' {
        Mock Test-LabNetwork { [PSCustomObject]@{ Exists = $true; SwitchName = 'SimpleLab'; SwitchType = 'Internal' } }
        $result = New-LabSwitch -Force
        Should -Invoke Remove-VMSwitch -Times 1 -Exactly
        Should -Invoke New-VMSwitch -Times 1 -Exactly
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = New-LabSwitch
        $result.Status | Should -Be 'Failed'
    }

    It 'accepts custom switch name' {
        $result = New-LabSwitch -SwitchName 'CustomLab'
        $result.SwitchName | Should -Be 'CustomLab'
    }
}

Describe 'Remove-LabSwitch' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with Status property' {
        $result = Remove-LabSwitch
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Status'
    }
}

Describe 'New-LabNAT' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with Status property' {
        $result = New-LabNAT
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Status'
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = New-LabNAT
        $result.Status | Should -Be 'Failed'
    }
}

Describe 'Initialize-LabNetwork' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with OverallStatus property' {
        $result = Initialize-LabNetwork
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }
}

Describe 'Test-LabNetwork' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with Exists property' {
        $result = Test-LabNetwork
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Exists'
    }

    It 'returns false when no switch found' {
        Mock Get-VMSwitch { @() }
        $result = Test-LabNetwork
        $result.Exists | Should -BeFalse
    }
}

Describe 'Test-LabNetworkHealth' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with OverallStatus property' {
        $result = Test-LabNetworkHealth
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }
}
