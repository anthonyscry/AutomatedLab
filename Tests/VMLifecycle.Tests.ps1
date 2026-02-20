# VMLifecycle.Tests.ps1 -- Unit tests for VM lifecycle Public functions
# Covers: New-LabVM, Remove-LabVM, Remove-LabVMs, Start-LabVMs, Stop-LabVMs,
#          Restart-LabVM, Restart-LabVMs, Suspend-LabVM, Suspend-LabVMs,
#          Resume-LabVM, Initialize-LabVMs

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    # Source all VM lifecycle Public functions
    . (Join-Path $script:repoRoot 'Public' 'New-LabVM.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Remove-LabVM.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Remove-LabVMs.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Start-LabVMs.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Stop-LabVMs.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Restart-LabVM.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Restart-LabVMs.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Suspend-LabVM.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Suspend-LabVMs.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Resume-LabVM.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Initialize-LabVMs.ps1')

    # Stub dependencies that these functions call
    if (-not (Get-Command Test-LabVM -ErrorAction SilentlyContinue)) {
        function Test-LabVM { param([string]$VMName) [PSCustomObject]@{ Exists = $false; VMName = $VMName } }
    }
    if (-not (Get-Command Get-LabVMConfig -ErrorAction SilentlyContinue)) {
        function Get-LabVMConfig { @{ dc1 = @{ Name = 'dc1' }; svr1 = @{ Name = 'svr1' }; ws1 = @{ Name = 'ws1' } } }
    }
    if (-not (Get-Command Write-LabStatus -ErrorAction SilentlyContinue)) {
        function Write-LabStatus { param($Status, $Message, $Indent) }
    }
}

Describe 'New-LabVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Test-LabVM { [PSCustomObject]@{ Exists = $false; VMName = $VMName } }
        Mock Get-Item { [PSCustomObject]@{ PSDrive = [PSCustomObject]@{ Name = 'C' } } }
        Mock Get-PSDrive { [PSCustomObject]@{ Free = 100GB } }
    }

    It 'returns result object with correct properties' {
        $result = New-LabVM -VMName 'testvm' -MemoryGB 4 -VHDPath 'C:\VMs\testvm.vhdx'
        $result | Should -Not -BeNullOrEmpty
        $result.VMName | Should -Be 'testvm'
        $result.MemoryGB | Should -Be 4
        $result.ProcessorCount | Should -Be 2
    }

    It 'creates VM and returns OK status on success' {
        $result = New-LabVM -VMName 'testvm' -MemoryGB 4 -VHDPath 'C:\VMs\testvm.vhdx'
        $result.Status | Should -Be 'OK'
        $result.Created | Should -BeTrue
        Should -Invoke New-VM -Times 1 -Exactly
        Should -Invoke Set-VMProcessor -Times 1 -Exactly
        Should -Invoke Set-VMMemory -Times 1 -Exactly
    }

    It 'returns AlreadyExists when VM exists and Force not specified' {
        Mock Test-LabVM { [PSCustomObject]@{ Exists = $true; VMName = $VMName } }
        $result = New-LabVM -VMName 'testvm' -MemoryGB 4 -VHDPath 'C:\VMs\testvm.vhdx'
        $result.Status | Should -Be 'AlreadyExists'
        $result.Created | Should -BeFalse
    }

    It 'removes and recreates VM when Force is specified' {
        Mock Test-LabVM { [PSCustomObject]@{ Exists = $true; VMName = $VMName } }
        $result = New-LabVM -VMName 'testvm' -MemoryGB 4 -VHDPath 'C:\VMs\testvm.vhdx' -Force
        Should -Invoke Remove-VM -Times 1 -Exactly
        Should -Invoke New-VM -Times 1 -Exactly
    }

    It 'returns Failed when Hyper-V module is not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = New-LabVM -VMName 'testvm' -MemoryGB 4 -VHDPath 'C:\VMs\testvm.vhdx'
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -BeLike '*Hyper-V*not available*'
    }
}

Describe 'Remove-LabVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Test-LabVM { [PSCustomObject]@{ Exists = $true; VMName = $VMName } }
        Mock Get-VM { New-MockVM -Name $Name -State 'Off' }
    }

    It 'removes VM and returns OK status' {
        $result = Remove-LabVM -VMName 'testvm'
        $result.Removed | Should -BeTrue
        $result.Status | Should -Be 'OK'
        Should -Invoke Remove-VM -Times 1 -Exactly
    }

    It 'returns NotFound when VM does not exist' {
        Mock Test-LabVM { [PSCustomObject]@{ Exists = $false; VMName = $VMName } }
        $result = Remove-LabVM -VMName 'noexist'
        $result.Status | Should -Be 'NotFound'
        $result.Removed | Should -BeFalse
    }

    It 'stops running VM before removal' {
        Mock Get-VM { New-MockVM -Name $Name -State 'Running' }
        $result = Remove-LabVM -VMName 'testvm'
        Should -Invoke Stop-VM -Times 1 -Exactly
    }
}

Describe 'Remove-LabVMs' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name -State 'Running' }
        Mock Remove-LabVM { [PSCustomObject]@{ VMName = $VMName; Removed = $true; OverallStatus = 'OK'; VHDDeleted = $false; Message = 'OK' } }
    }

    It 'returns result object with expected properties' {
        $result = Remove-LabVMs -Force
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V module not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Remove-LabVMs -Force
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Start-LabVMs' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name -State 'Off' }
    }

    It 'returns result with OverallStatus property' {
        $result = Start-LabVMs
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V module not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Start-LabVMs
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Stop-LabVMs' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name -State 'Running' }
    }

    It 'returns result with OverallStatus property' {
        $result = Stop-LabVMs
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V module not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Stop-LabVMs
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Restart-LabVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $VMName -State 'Running' }
    }

    It 'returns result with expected properties' {
        $result = Restart-LabVM -VMName 'dc1'
        $result | Should -Not -BeNullOrEmpty
        $result.VMName | Should -Be 'dc1'
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns NotFound when VM does not exist' {
        Mock Get-VM { $null }
        $result = Restart-LabVM -VMName 'noexist'
        $result.OverallStatus | Should -Be 'NotFound'
    }

    It 'returns Failed when Hyper-V module not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Restart-LabVM -VMName 'dc1'
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Restart-LabVMs' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with OverallStatus property' {
        $result = Restart-LabVMs
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }
}

Describe 'Suspend-LabVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $VMName -State 'Running' }
    }

    It 'returns result with expected properties' {
        $result = Suspend-LabVM -VMName 'dc1'
        $result | Should -Not -BeNullOrEmpty
        $result.VMName | Should -Be 'dc1'
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns NotFound when VM does not exist' {
        Mock Get-VM { $null }
        $result = Suspend-LabVM -VMName 'noexist'
        $result.OverallStatus | Should -Be 'NotFound'
    }
}

Describe 'Suspend-LabVMs' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with OverallStatus property' {
        $result = Suspend-LabVMs
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }
}

Describe 'Resume-LabVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $VMName -State 'Saved' }
    }

    It 'returns result with expected properties' {
        $result = Resume-LabVM -VMName 'dc1'
        $result | Should -Not -BeNullOrEmpty
        $result.VMName | Should -Be 'dc1'
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns NotFound when VM does not exist' {
        Mock Get-VM { $null }
        $result = Resume-LabVM -VMName 'noexist'
        $result.OverallStatus | Should -Be 'NotFound'
    }
}

Describe 'Initialize-LabVMs' {
    BeforeEach {
        Register-HyperVMocks
    }

    It 'returns result with expected properties' {
        $result = Initialize-LabVMs
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }
}
