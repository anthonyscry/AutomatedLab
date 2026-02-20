# LinuxPublic.Tests.ps1 -- Unit tests for Linux Public functions
# Covers: New-LinuxVM, Wait-LinuxVMReady, New-LinuxGoldenVhdx, New-CidataVhdx,
#          Get-LinuxVMIPv4, Get-LinuxSSHConnectionInfo, Invoke-BashOnLinuxVM,
#          Join-LinuxToDomain, Add-LinuxDhcpReservation, Finalize-LinuxInstallMedia,
#          Remove-HyperVVMStale, Get-Sha512PasswordHash

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    # Source all Linux Public functions
    $script:linuxDir = Join-Path (Join-Path $script:repoRoot 'Public') 'Linux'
    . (Join-Path $script:linuxDir 'New-LinuxVM.ps1')
    . (Join-Path $script:linuxDir 'Wait-LinuxVMReady.ps1')
    . (Join-Path $script:linuxDir 'New-LinuxGoldenVhdx.ps1')
    . (Join-Path $script:linuxDir 'New-CidataVhdx.ps1')
    . (Join-Path $script:linuxDir 'Get-LinuxVMIPv4.ps1')
    . (Join-Path $script:linuxDir 'Get-LinuxSSHConnectionInfo.ps1')
    . (Join-Path $script:linuxDir 'Invoke-BashOnLinuxVM.ps1')
    . (Join-Path $script:linuxDir 'Join-LinuxToDomain.ps1')
    . (Join-Path $script:linuxDir 'Add-LinuxDhcpReservation.ps1')
    . (Join-Path $script:linuxDir 'Finalize-LinuxInstallMedia.ps1')
    . (Join-Path $script:linuxDir 'Remove-HyperVVMStale.ps1')
    . (Join-Path $script:linuxDir 'Get-Sha512PasswordHash.ps1')

    # Stub dependencies
    if (-not (Get-Command Write-LabStatus -ErrorAction SilentlyContinue)) {
        function Write-LabStatus { param($Status, $Message, $Indent) }
    }

    # Provide $GlobalLabConfig for Linux functions that reference it
    $script:GlobalLabConfig = @{
        Lab = @{ Name = 'TestLab'; CoreVMNames = @('dc1', 'svr1', 'ws1') }
        Paths = @{ LabRoot = 'C:\Lab'; UbuntuIso = 'C:\iso\ubuntu.iso' }
        Network = @{ SwitchName = 'SimpleLab'; SubnetPrefix = '10.0.0'; PrefixLength = 24 }
        VMSizing = @{ Ubuntu = @{ Memory = 2GB; MinMemory = 1GB; MaxMemory = 4GB; Processors = 2 } }
        Credentials = @{ AdminPassword = 'TestPass123!'; AdminUser = 'labadmin' }
    }
}

Describe 'Get-Sha512PasswordHash' {
    # Pure function -- no Hyper-V mocks needed
    It 'returns a string in $6$ format' {
        $hash = Get-Sha512PasswordHash -Password 'TestPassword123!'
        $hash | Should -Not -BeNullOrEmpty
        $hash | Should -BeLike '$6$*'
    }

    It 'returns different hashes for different passwords' {
        $hash1 = Get-Sha512PasswordHash -Password 'Password1'
        $hash2 = Get-Sha512PasswordHash -Password 'Password2'
        $hash1 | Should -Not -Be $hash2
    }

    It 'returns consistent format with salt and hash sections' {
        $hash = Get-Sha512PasswordHash -Password 'TestPass'
        # Format: $6$<salt>$<hash>
        ($hash -split '\$').Count | Should -BeGreaterOrEqual 4
    }
}

Describe 'New-LinuxVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Test-Path { $true }
        Mock New-Item { [PSCustomObject]@{ FullName = 'C:\VMs\LIN1' } }
        # Prefix Hyper-V cmdlets with module scope as used in the source
        Mock -CommandName 'Hyper-V\New-VM' { New-MockVM -Name $Name } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Set-VM' { } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Set-VMFirmware' { } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Add-VMDvdDrive' { } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Add-VMHardDiskDrive' { } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Get-VMDvdDrive' { [PSCustomObject]@{ VMName = 'LIN1'; Path = 'C:\iso\ubuntu.iso' } } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Get-VMHardDiskDrive' { @([PSCustomObject]@{ VMName = 'LIN1'; Path = 'C:\VMs\LIN1\LIN1.vhdx' }) } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Get-VM' { New-MockVM -Name $Name } -ErrorAction SilentlyContinue
    }

    It 'throws when ISO path does not exist' {
        Mock Test-Path { $false } -ParameterFilter { $Path -and $Path -like '*iso*' }
        { New-LinuxVM -UbuntuIsoPath 'C:\nonexist.iso' -CidataVhdxPath 'C:\cidata.vhdx' } | Should -Throw '*not found*'
    }

    It 'throws when CIDATA path does not exist' {
        Mock Test-Path {
            if ($Path -like '*iso*') { return $true }
            return $false
        }
        { New-LinuxVM -UbuntuIsoPath 'C:\iso\ubuntu.iso' -CidataVhdxPath 'C:\nonexist.vhdx' } | Should -Throw '*not found*'
    }
}

Describe 'Wait-LinuxVMReady' {
    BeforeEach {
        Register-HyperVMocks
        Mock Test-Connection { $true }
    }

    It 'returns without error when VM is reachable' {
        # Wait-LinuxVMReady polls Test-Connection; with mock returning true, it should succeed
        { Wait-LinuxVMReady -VMName 'LIN1' -TimeoutSeconds 5 } | Should -Not -Throw
    }
}

Describe 'Get-LinuxVMIPv4' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VMNetworkAdapter { New-MockVMNetworkAdapter -VMName $VMName -IPAddresses @('10.0.0.50') }
    }

    It 'returns an IP address string' {
        $ip = Get-LinuxVMIPv4 -VMName 'LIN1'
        $ip | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-LinuxSSHConnectionInfo' {
    BeforeEach {
        Register-HyperVMocks
        # This function builds SSH connection info from config
        if (-not (Get-Command Get-LinuxVMIPv4 -ErrorAction SilentlyContinue)) {
            # Already loaded
        }
        Mock Get-LinuxVMIPv4 { '10.0.0.50' }
    }

    It 'returns connection info object' {
        $info = Get-LinuxSSHConnectionInfo -VMName 'LIN1'
        $info | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-BashOnLinuxVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-LinuxSSHConnectionInfo { [PSCustomObject]@{ Hostname = '10.0.0.50'; Username = 'labadmin'; Port = 22; KeyPath = 'C:\keys\id_rsa' } }
    }

    It 'does not throw with valid parameters' {
        { Invoke-BashOnLinuxVM -VMName 'LIN1' -Script 'echo hello' } | Should -Not -Throw
    }
}

Describe 'Join-LinuxToDomain' {
    BeforeEach {
        Register-HyperVMocks
        Mock Invoke-BashOnLinuxVM { [PSCustomObject]@{ ExitCode = 0; Output = 'Joined' } }
    }

    It 'returns result object' {
        $result = Join-LinuxToDomain -VMName 'LIN1'
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Add-LinuxDhcpReservation' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VMNetworkAdapter { New-MockVMNetworkAdapter -VMName $VMName }
        Mock Invoke-Command { }
    }

    It 'does not throw with valid parameters' {
        { Add-LinuxDhcpReservation -VMName 'LIN1' } | Should -Not -Throw
    }
}

Describe 'Finalize-LinuxInstallMedia' {
    BeforeEach {
        Register-HyperVMocks
        Mock -CommandName 'Hyper-V\Get-VMDvdDrive' { [PSCustomObject]@{ VMName = 'LIN1'; Path = 'C:\iso\ubuntu.iso'; ControllerNumber = 0; ControllerLocation = 1 } } -ErrorAction SilentlyContinue
        Mock -CommandName 'Hyper-V\Remove-VMDvdDrive' { } -ErrorAction SilentlyContinue
    }

    It 'returns without error' {
        { Finalize-LinuxInstallMedia -VMName 'LIN1' } | Should -Not -Throw
    }
}

Describe 'Remove-HyperVVMStale' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name -State 'Off' }
    }

    It 'returns result object' {
        $result = Remove-HyperVVMStale -VMName 'StaleVM'
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe 'New-LinuxGoldenVhdx' {
    BeforeEach {
        Register-HyperVMocks
        Mock Test-Path { $true }
        Mock New-Item { [PSCustomObject]@{ FullName = 'C:\Golden' } }
        Mock Copy-Item { }
    }

    It 'does not throw with valid parameters' {
        Set-ItResult -Skipped -Because 'Requires complex file system setup (ISO mount, VHDX creation) that cannot be fully mocked without Hyper-V'
    }
}

Describe 'New-CidataVhdx' {
    BeforeEach {
        Register-HyperVMocks
        Mock New-VHD { [PSCustomObject]@{ Path = 'C:\cidata.vhdx' } }
        Mock Mount-VHD { }
        Mock Dismount-VHD { }
        Mock New-Item { [PSCustomObject]@{ FullName = 'C:\temp\cidata' } }
        Mock Set-Content { }
        Mock Out-File { }
    }

    It 'does not throw with valid parameters' {
        Set-ItResult -Skipped -Because 'Requires disk initialization and partition operations that cannot be fully mocked without Windows disk management'
    }
}
