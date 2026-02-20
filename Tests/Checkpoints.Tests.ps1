# Checkpoints.Tests.ps1 -- Unit tests for checkpoint Public functions
# Covers: Get-LabCheckpoint, Save-LabCheckpoint, Restore-LabCheckpoint, Save-LabReadyCheckpoint

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    . (Join-Path $script:repoRoot 'Public' 'Get-LabCheckpoint.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Save-LabCheckpoint.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Restore-LabCheckpoint.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Save-LabReadyCheckpoint.ps1')

    # Stub dependencies
    if (-not (Get-Command Get-LabVMConfig -ErrorAction SilentlyContinue)) {
        function Get-LabVMConfig { @{ dc1 = @{ Name = 'dc1' }; svr1 = @{ Name = 'svr1' }; ws1 = @{ Name = 'ws1' } } }
    }
    if (-not (Get-Command Write-LabStatus -ErrorAction SilentlyContinue)) {
        function Write-LabStatus { param($Status, $Message, $Indent) }
    }
}

Describe 'Get-LabCheckpoint' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name }
        Mock Get-VMCheckpoint { @(New-MockVMSnapshot -VMName $VMName -Name 'LabReady') }
    }

    It 'returns array of checkpoint objects' {
        $results = Get-LabCheckpoint
        $results | Should -Not -BeNullOrEmpty
    }

    It 'returns objects with expected properties' {
        $results = Get-LabCheckpoint
        $first = $results | Select-Object -First 1
        $first.PSObject.Properties.Name | Should -Contain 'VMName'
        $first.PSObject.Properties.Name | Should -Contain 'CheckpointName'
        $first.PSObject.Properties.Name | Should -Contain 'Status'
    }

    It 'returns empty array when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $results = Get-LabCheckpoint
        @($results).Count | Should -Be 0
    }

    It 'handles VMs with no checkpoints' {
        Mock Get-VMCheckpoint { @() }
        $results = Get-LabCheckpoint
        $noCheckpoint = $results | Where-Object { $_.CheckpointName -eq 'None' }
        $noCheckpoint | Should -Not -BeNullOrEmpty
    }
}

Describe 'Save-LabCheckpoint' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name }
    }

    It 'returns result with OverallStatus property' {
        $result = Save-LabCheckpoint
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'calls Checkpoint-VM for lab VMs' {
        $result = Save-LabCheckpoint
        Should -Invoke Checkpoint-VM -Times 1 -Exactly -Scope It
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Save-LabCheckpoint
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Restore-LabCheckpoint' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name -State 'Off' }
        Mock Get-VMSnapshot { @(New-MockVMSnapshot -VMName $VMName -Name 'LabReady') }
    }

    It 'returns result with OverallStatus property' {
        $result = Restore-LabCheckpoint
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Restore-LabCheckpoint
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Save-LabReadyCheckpoint' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name }
    }

    It 'returns result with OverallStatus property' {
        $result = Save-LabReadyCheckpoint
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Save-LabReadyCheckpoint
        $result.OverallStatus | Should -Be 'Failed'
    }
}
