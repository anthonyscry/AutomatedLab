# New-LinuxVM.ps1 -- Create Linux Hyper-V VM with install media
function New-LinuxVM {
    <#
    .SYNOPSIS
    Create Hyper-V Gen2 VM for a Linux Ubuntu 24.04 guest.

    Creates the VM, attaches the Ubuntu ISO as DVD for boot, and attaches
    the CIDATA VHDX as a second SCSI disk for cloud-init NoCloud discovery.

    .PARAMETER UbuntuIsoPath
    Path to Ubuntu 24.04 installation ISO.

    .PARAMETER CidataVhdxPath
    Path to CIDATA VHDX seed disk (from New-CidataVhdx).

    .PARAMETER VMName
    Name for the virtual machine (default: LIN1).

    .PARAMETER VhdxPath
    Path for the OS VHDX file (default: auto-generated under $LabPath).

    .PARAMETER SwitchName
    Hyper-V switch name (default: from Lab-Config.ps1 $LabSwitch).

    .PARAMETER Memory
    Startup memory (default: from Lab-Config.ps1 $UBU_Memory).

    .PARAMETER MinMemory
    Minimum memory (default: from Lab-Config.ps1 $UBU_MinMemory).

    .PARAMETER MaxMemory
    Maximum memory (default: from Lab-Config.ps1 $UBU_MaxMemory).

    .PARAMETER Processors
    Processor count (default: from Lab-Config.ps1 $UBU_Processors).

    .PARAMETER DiskSize
    OS disk size (default: 60GB).

    .OUTPUTS
    Microsoft.HyperV.PowerShell.VirtualMachine object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UbuntuIsoPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CidataVhdxPath,
        [string]$VMName = 'LIN1',
        [string]$VhdxPath = '',
        [string]$SwitchName = $(if ($LabSwitch) { $LabSwitch } else { 'AutomatedLab' }),
        [long]$Memory = $(if ($UBU_Memory) { $UBU_Memory } else { 2GB }),
        [long]$MinMemory = $(if ($UBU_MinMemory) { $UBU_MinMemory } else { 1GB }),
        [long]$MaxMemory = $(if ($UBU_MaxMemory) { $UBU_MaxMemory } else { 4GB }),
        [int]$Processors = $(if ($UBU_Processors) { $UBU_Processors } else { 2 }),
        [long]$DiskSize = 60GB
    )

    if (-not (Test-Path $UbuntuIsoPath)) { throw "Ubuntu ISO not found: $UbuntuIsoPath" }
    if (-not (Test-Path $CidataVhdxPath)) { throw "CIDATA VHDX not found: $CidataVhdxPath" }

    if (-not $VhdxPath) {
        $VhdxPath = Join-Path $LabPath "$VMName\$VMName.vhdx"
    }
    $vhdxDir = Split-Path $VhdxPath -Parent
    if ($vhdxDir) { New-Item -ItemType Directory -Path $vhdxDir -Force | Out-Null }

    # Create Gen2 VM with dynamic memory
    $vm = Hyper-V\New-VM -Name $VMName -Generation 2 `
        -MemoryStartupBytes $Memory `
        -NewVHDPath $VhdxPath -NewVHDSizeBytes $DiskSize `
        -SwitchName $SwitchName -ErrorAction Stop

    Hyper-V\Set-VM -VM $vm -DynamicMemory `
        -MemoryMinimumBytes $MinMemory -MemoryMaximumBytes $MaxMemory `
        -ProcessorCount $Processors `
        -AutomaticCheckpointsEnabled $false -ErrorAction Stop

    # Disable Secure Boot (required for Ubuntu on Gen2)
    Hyper-V\Set-VMFirmware -VM $vm -EnableSecureBoot Off -ErrorAction Stop

    # Attach Ubuntu ISO as DVD for installation boot
    Hyper-V\Add-VMDvdDrive -VM $vm -Path $UbuntuIsoPath -ErrorAction Stop

    # Attach CIDATA VHDX as second SCSI disk (cloud-init NoCloud seed)
    Hyper-V\Add-VMHardDiskDrive -VM $vm -Path $CidataVhdxPath -ErrorAction Stop

    # Set boot order: DVD first (Ubuntu ISO), then hard disk (OS)
    $dvd = Hyper-V\Get-VMDvdDrive -VM $vm | Select-Object -First 1
    $hdd = Hyper-V\Get-VMHardDiskDrive -VM $vm | Where-Object { $_.Path -eq $VhdxPath } | Select-Object -First 1
    Hyper-V\Set-VMFirmware -VM $vm -BootOrder $dvd, $hdd -ErrorAction Stop

    Write-LabStatus -Status OK -Message "VM '$VMName' created (Gen2, SecureBoot=Off, DVD+CIDATA)" -Indent 2
    return Hyper-V\Get-VM -Name $VMName
}
