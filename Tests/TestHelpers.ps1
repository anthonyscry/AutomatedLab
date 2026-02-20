# TestHelpers.ps1 -- Shared Hyper-V mock infrastructure for Public function tests
# Dot-source this file in BeforeAll blocks. Call Register-HyperVMocks inside Describe/Context blocks.

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function New-MockVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$State = 'Running',

        [Parameter()]
        [long]$MemoryAssigned = 4GB,

        [Parameter()]
        [long]$MemoryStartup = 4GB,

        [Parameter()]
        [int]$ProcessorCount = 2,

        [Parameter()]
        [int]$CPUUsage = 5
    )

    [PSCustomObject]@{
        Name                  = $Name
        VMName                = $Name
        State                 = $State
        MemoryAssigned        = $MemoryAssigned
        MemoryStartup         = $MemoryStartup
        ProcessorCount        = $ProcessorCount
        CPUUsage              = $CPUUsage
        Status                = 'Operating normally'
        Uptime                = (New-TimeSpan -Hours 1 -Minutes 30)
        Path                  = "C:\Hyper-V\$Name"
        CheckpointFileLocation = "C:\Hyper-V\$Name\Snapshots"
        ParentSnapshotId      = $null
        ParentSnapshotName    = $null
        VMId                  = [guid]::NewGuid()
        Heartbeat             = if ($State -eq 'Running') { 'Ok' } else { $null }
        HardDrives            = @([PSCustomObject]@{ Path = "C:\Hyper-V\$Name\$Name.vhdx" })
    }
}

function New-MockVMSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$SwitchType = 'Internal'
    )

    [PSCustomObject]@{
        Name                          = $Name
        SwitchType                    = $SwitchType
        NetAdapterInterfaceDescription = ''
        AllowManagementOS             = $true
    }
}

function New-MockVMSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter()]
        [string]$Name = 'LabReady',

        [Parameter()]
        [datetime]$CreationTime
    )

    if (-not $CreationTime) { $CreationTime = (Get-Date).AddHours(-2) }

    [PSCustomObject]@{
        VMName             = $VMName
        Name               = $Name
        CreationTime       = $CreationTime
        ParentSnapshotName = $null
        SnapshotType       = 'Standard'
        IsSnapshot         = $true
    }
}

function New-MockNetNat {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name = 'LabNAT',

        [Parameter()]
        [string]$InternalIPInterfaceAddressPrefix = '10.0.0.0/24'
    )

    [PSCustomObject]@{
        Name                             = $Name
        InternalIPInterfaceAddressPrefix = $InternalIPInterfaceAddressPrefix
        Active                           = $true
    }
}

function New-MockVMNetworkAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter()]
        [string]$SwitchName = 'SimpleLab',

        [Parameter()]
        [string[]]$IPAddresses = @('10.0.0.10')
    )

    [PSCustomObject]@{
        VMName     = $VMName
        SwitchName = $SwitchName
        Status     = 'Ok'
        IPAddresses = $IPAddresses
        MacAddress  = '00155D010203'
    }
}

function Register-HyperVMocks {
    <#
    .SYNOPSIS
        Registers Pester mocks for all Hyper-V and infrastructure cmdlets.
        Must be called inside a Describe/Context BeforeEach or BeforeAll block.
    #>
    [CmdletBinding()]
    param()

    # --- Hyper-V VM cmdlets ---
    Mock Get-VM { @() }
    Mock New-VM { New-MockVM -Name $Name }
    Mock Set-VM { }
    Mock Start-VM { }
    Mock Stop-VM { }
    Mock Restart-VM { }
    Mock Suspend-VM { }
    Mock Resume-VM { }
    Mock Remove-VM { }
    Mock Set-VMMemory { }
    Mock Set-VMProcessor { }
    Mock Enable-VMIntegrationService { }

    # --- Hyper-V switch cmdlets ---
    Mock Get-VMSwitch { @() }
    Mock New-VMSwitch { New-MockVMSwitch -Name $Name }
    Mock Remove-VMSwitch { }

    # --- Hyper-V snapshot/checkpoint cmdlets ---
    Mock Get-VMSnapshot { @() }
    Mock Get-VMCheckpoint { @() }
    Mock Checkpoint-VM { }
    Mock Restore-VMSnapshot { }
    Mock Remove-VMSnapshot { }

    # --- Hyper-V network adapter cmdlets ---
    Mock Get-VMNetworkAdapter { @() }
    Mock Set-VMNetworkAdapter { }
    Mock Add-VMNetworkAdapter { }
    Mock Connect-VMNetworkAdapter { }

    # --- Hyper-V disk/firmware cmdlets ---
    Mock Get-VMHardDiskDrive { @() }
    Mock Add-VMHardDiskDrive { }
    Mock Get-VMDvdDrive { [PSCustomObject]@{ VMName = 'mock'; Path = 'C:\mock.iso' } }
    Mock Add-VMDvdDrive { }
    Mock Set-VMFirmware { }
    Mock Get-VMFirmware { [PSCustomObject]@{ BootOrder = @() } }
    Mock Mount-VHD { }
    Mock Dismount-VHD { }
    Mock New-VHD { [PSCustomObject]@{ Path = 'C:\mock.vhdx' } }
    Mock Get-VHD { [PSCustomObject]@{ Path = 'C:\mock.vhdx'; Size = 60GB } }

    # --- NAT cmdlets ---
    Mock Get-NetNat { @() }
    Mock New-NetNat { New-MockNetNat }
    Mock Remove-NetNat { }

    # --- Network testing ---
    Mock Test-Connection { $true }
    Mock Resolve-DnsName { [PSCustomObject]@{ Name = 'dc1.lab.local'; IPAddress = '10.0.0.10' } }

    # --- Remote execution ---
    Mock Invoke-Command { $null }

    # --- Module availability (Hyper-V not in CI) ---
    Mock Get-Module {
        if ($ListAvailable -and $Name -eq 'Hyper-V') {
            return [PSCustomObject]@{ Name = 'Hyper-V'; Version = '2.0.0.0' }
        }
        return $null
    } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }

    # --- Sleep mocks (speed up tests) ---
    Mock Start-Sleep { }

    # --- Job mocks for parallel operations ---
    Mock Start-Job { [PSCustomObject]@{ Id = 1; State = 'Completed' } }
    Mock Wait-Job { }
    Mock Receive-Job { [PSCustomObject]@{ VMName = 'mock'; Success = $true; ErrorMessage = '' } }
    Mock Remove-Job { }
    Mock Stop-Job { }
}
