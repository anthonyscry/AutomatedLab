# Lab-Common.ps1 -- Shared helpers for OpenCode Dev Lab workflow scripts

Set-StrictMode -Version Latest

function Import-OpenCodeLab {
    param([string]$Name)

    try {
        Import-Module AutomatedLab -ErrorAction Stop | Out-Null
    } catch {
        throw "AutomatedLab module not available. Install AutomatedLab first."
    }

    try {
        Import-Lab -Name $Name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Ensure-VMRunning {
    param(
        [Parameter(Mandatory)] [string[]] $VMNames,
        [switch] $AutoStart
    )
    $missing = @()
    foreach ($n in $VMNames) {
        $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
        if (-not $vm) { $missing += $n; continue }
        if ($vm.State -ne 'Running') {
            if ($AutoStart) {
                Start-VM -Name $n -ErrorAction SilentlyContinue | Out-Null
            } else {
                return $false
            }
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing Hyper-V VM(s): $($missing -join ', ')"
    }
    # If we autostarted, wait a moment for adapters to populate
    Start-Sleep -Seconds 2
    return $true
}

function Ensure-VMsReady {
    param(
        [Parameter(Mandatory)][string[]]$VMNames,
        [switch]$NonInteractive,
        [switch]$AutoStart
    )
    if (-not (Ensure-VMRunning -VMNames $VMNames)) {
        if ($NonInteractive -or $AutoStart) {
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        } else {
            $vmList = $VMNames -join ', '
            $start = Read-Host "  $vmList not running. Start now? (y/n)"
            if ($start -ne 'y') { exit 0 }
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        }
    }
}

function Get-LIN1IPv4 {
    $ip = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
        Select-Object -First 1
    return $ip
}

function Ensure-SSHKey {
    param([string]$KeyPath)
    if (-not (Test-Path $KeyPath)) {
        throw "SSH key not found: $KeyPath`nGenerate it with: C:\Windows\System32\OpenSSH\ssh-keygen.exe -t ed25519 -f `"$KeyPath`" -N `"`""
    }
}

function Get-GitIdentity {
    param([string]$DefaultName, [string]$DefaultEmail)

    $name  = $DefaultName
    $email = $DefaultEmail

    if ([string]::IsNullOrWhiteSpace($name))  { $name  = Read-Host "  Git user.name (e.g. Anthony Tran)" }
    if ([string]::IsNullOrWhiteSpace($email)) { $email = Read-Host "  Git user.email (e.g. you@domain)" }

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($email)) {
        throw "Git identity is required."
    }

    return @{ Name = $name; Email = $email }
}

function Invoke-BashOnLIN1 {
    param(
        [Parameter(Mandatory)][string]$BashScript,
        [Parameter(Mandatory)][string]$ActivityName,
        [hashtable]$Variables = @{},
        [switch]$PassThru
    )
    # Apply variable substitutions (placeholder pattern: __KEY__)
    $content = $BashScript
    foreach ($key in $Variables.Keys) {
        $content = $content.Replace("__${key}__", $Variables[$key])
    }

    $tempName = "$ActivityName-$(Get-Date -Format 'HHmmss').sh"
    $tempPath = Join-Path $env:TEMP $tempName
    $content | Set-Content -Path $tempPath -Encoding ASCII -Force

    try {
        Copy-LabFileItem -Path $tempPath -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

        $invokeParams = @{
            ComputerName = 'LIN1'
            ActivityName = $ActivityName
            ScriptBlock = {
                param($ScriptFile)
                chmod +x "/tmp/$ScriptFile"
                bash "/tmp/$ScriptFile"
            }
            ArgumentList = @($tempName)
        }
        if ($PassThru) { $invokeParams.PassThru = $true }

        Invoke-LabCommand @invokeParams
    } finally {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-Sha512PasswordHash {
    <#
    .SYNOPSIS
    Generate SHA512 crypt hash for Ubuntu autoinstall identity section.
    
    .PARAMETER Password
    The plain-text password to hash.
    
    .OUTPUTS
    String in $6$salt$hash format suitable for Ubuntu user-data password field.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Password
    )

    # Try OpenSSL first (if available)
    $opensslPaths = @(
        'C:\Program Files\OpenSSL-Win64\bin\openssl.exe',
        'C:\Program Files\OpenSSL\bin\openssl.exe',
        'C:\OpenSSL-Win64\bin\openssl.exe'
    )
    
    foreach ($opensslPath in $opensslPaths) {
        if (Test-Path $opensslPath) {
            try {
                $hash = & $opensslPath passwd -6 $Password 2>$null
                if ($LASTEXITCODE -eq 0 -and $hash -match '^\$6\$') {
                    return $hash.Trim()
                }
            } catch {
                # Continue to next path or .NET fallback
            }
        }
    }
    
    # Fallback: Use .NET crypto for SHA512 crypt hash generation
    Add-Type -AssemblyName System.Security
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $saltBytes = New-Object byte[] 16
    $rng.GetBytes($saltBytes)
    
    # Convert to base64-like charset for crypt salt [a-zA-Z0-9./]
    $saltChars = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    $salt = -join ($saltBytes | ForEach-Object { $saltChars[$_ % 64] })
    $salt = $salt.Substring(0, 16)
    
    # SHA512 crypt implementation (simplified - uses .NET SHA512)
    $sha512 = [System.Security.Cryptography.SHA512]::Create()
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $saltBytesActual = [System.Text.Encoding]::UTF8.GetBytes($salt)
    
    # Combine password and salt
    $combined = $passwordBytes + $saltBytesActual + $passwordBytes
    $hash = $sha512.ComputeHash($combined)
    
    # Base64-encode for crypt format
    $hashB64 = -join ($hash | ForEach-Object { $saltChars[$_ % 64] })
    
    return "`$6`$$salt`$$hashB64"
}

function New-CidataVhdx {
    <#
    .SYNOPSIS
    Create a CIDATA VHDX seed disk for Ubuntu 24.04 autoinstall.

    Uses a small FAT32-formatted VHDX with volume label "CIDATA" containing
    user-data and meta-data files. Cloud-init NoCloud datasource detects any
    filesystem labeled "CIDATA"/"cidata" -- no ISO tools (oscdimg) required.

    .PARAMETER OutputPath
    Path where the VHDX file will be created.

    .PARAMETER Hostname
    Hostname for the Ubuntu system.

    .PARAMETER Username
    Username for the initial user account.

    .PARAMETER PasswordHash
    SHA512 password hash (from Get-Sha512PasswordHash).

    .PARAMETER SSHPublicKey
    Optional SSH public key content to add to authorized_keys.

    .OUTPUTS
    Path to the created VHDX file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$PasswordHash,
        [string]$SSHPublicKey = ''
    )

    # Build autoinstall user-data for Ubuntu 24.04 Subiquity
    $sshBlock = ''
    if ($SSHPublicKey) {
        $sshBlock = @"

    authorized-keys:
      - $SSHPublicKey
"@
    }

    $userData = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    version: 2
    ethernets:
      eth0:
        dhcp4: true
  identity:
    hostname: $Hostname
    username: $Username
    password: '$PasswordHash'
  storage:
    layout:
      name: lvm
  ssh:
    install-server: true
    allow-pw: true$sshBlock
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  packages:
    - openssh-server
    - curl
    - wget
    - git
    - net-tools
"@

    $metaData = @"
instance-id: iid-$Hostname-$(Get-Date -Format 'yyyyMMddHHmmss')
local-hostname: $Hostname
"@

    # Staging folder for the two files
    $staging = Join-Path $env:TEMP ("cidata-" + [guid]::NewGuid().ToString().Substring(0,8))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    try {
        [IO.File]::WriteAllText((Join-Path $staging 'user-data'), $userData, $utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $staging 'meta-data'), $metaData, $utf8NoBom)

        # Create parent directory for the VHDX
        $dir = Split-Path $OutputPath -Parent
        if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

        # Create a small dynamic VHDX, partition, format FAT32 with label CIDATA
        New-VHD -Path $OutputPath -SizeBytes 64MB -Dynamic | Out-Null
        $mounted = Mount-VHD -Path $OutputPath -PassThru
        $diskNum = $mounted.DiskNumber

        Initialize-Disk -Number $diskNum -PartitionStyle GPT -PassThru | Out-Null
        $part = New-Partition -DiskNumber $diskNum -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Force | Out-Null

        $driveLetter = ($part | Get-Volume).DriveLetter
        $driveRoot = "${driveLetter}:\"
        Copy-Item (Join-Path $staging 'user-data') (Join-Path $driveRoot 'user-data') -Force
        Copy-Item (Join-Path $staging 'meta-data') (Join-Path $driveRoot 'meta-data') -Force

        Dismount-VHD -Path $OutputPath
        Write-Host "    [OK] CIDATA VHDX created: $OutputPath" -ForegroundColor Green
        return $OutputPath
    }
    catch {
        # Ensure VHD is dismounted on failure
        try { Dismount-VHD -Path $OutputPath -ErrorAction SilentlyContinue } catch {}
        throw
    }
    finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-LIN1VM {
    <#
    .SYNOPSIS
    Create Hyper-V Gen2 VM for LIN1 Ubuntu 24.04.

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
        [Parameter(Mandatory)][string]$UbuntuIsoPath,
        [Parameter(Mandatory)][string]$CidataVhdxPath,
        [string]$VMName = 'LIN1',
        [string]$VhdxPath = '',
        [string]$SwitchName = $LabSwitch,
        [long]$Memory = $UBU_Memory,
        [long]$MinMemory = $UBU_MinMemory,
        [long]$MaxMemory = $UBU_MaxMemory,
        [int]$Processors = $UBU_Processors,
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
        -SwitchName $SwitchName

    Hyper-V\Set-VM -VM $vm -DynamicMemory `
        -MemoryMinimumBytes $MinMemory -MemoryMaximumBytes $MaxMemory `
        -ProcessorCount $Processors `
        -AutomaticCheckpointsEnabled $false

    # Disable Secure Boot (required for Ubuntu on Gen2)
    Hyper-V\Set-VMFirmware -VM $vm -EnableSecureBoot Off

    # Attach Ubuntu ISO as DVD for installation boot
    Hyper-V\Add-VMDvdDrive -VM $vm -Path $UbuntuIsoPath

    # Attach CIDATA VHDX as second SCSI disk (cloud-init NoCloud seed)
    Hyper-V\Add-VMHardDiskDrive -VM $vm -Path $CidataVhdxPath

    # Set boot order: DVD first (Ubuntu ISO), then hard disk (OS)
    $dvd = Hyper-V\Get-VMDvdDrive -VM $vm | Select-Object -First 1
    $hdd = Hyper-V\Get-VMHardDiskDrive -VM $vm | Where-Object { $_.Path -eq $VhdxPath } | Select-Object -First 1
    Hyper-V\Set-VMFirmware -VM $vm -BootOrder $dvd, $hdd

    Write-Host "    [OK] VM '$VMName' created (Gen2, SecureBoot=Off, DVD+CIDATA)" -ForegroundColor Green
    return Hyper-V\Get-VM -Name $VMName
}
