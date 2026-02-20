# New-CidataVhdx.ps1 -- Create cloud-init CIDATA VHDX seed disk
function New-CidataVhdx {
    <#
    .SYNOPSIS
    Create a CIDATA VHDX seed disk for Linux cloud-init.

    .DESCRIPTION
    Uses a small FAT32-formatted VHDX with volume label "CIDATA" containing
    user-data and meta-data files. Cloud-init NoCloud datasource detects any
    filesystem labeled "CIDATA"/"cidata" -- no ISO tools (oscdimg) required.
    Supports Ubuntu 24.04, Ubuntu 22.04, and Rocky Linux 9 autoinstall formats.
    If the output VHDX already exists the function returns its path immediately
    (cache hit) without overwriting the existing disk.

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

    .PARAMETER Distro
    Target Linux distribution format: Ubuntu2404, Ubuntu2204, or Rocky9
    (default: Ubuntu2404).

    .OUTPUTS
    Path to the created VHDX file.

    .EXAMPLE
    $hash = Get-Sha512PasswordHash -Password 'P@ssw0rd!'
    $cidata = New-CidataVhdx -OutputPath 'C:\LabSources\cidata-lin1.vhdx' `
        -Hostname 'LIN1' -Username 'labadmin' -PasswordHash $hash
    # Creates a CIDATA seed disk and returns its path.

    .EXAMPLE
    $sshKey = Get-Content 'C:\LabSources\SSHKeys\id_ed25519.pub' -Raw
    $cidata = New-CidataVhdx -OutputPath 'C:\LabSources\cidata-lin2.vhdx' `
        -Hostname 'LIN2' -Username 'labadmin' -PasswordHash $hash `
        -SSHPublicKey $sshKey -Distro Ubuntu2204

    .EXAMPLE
    # Idempotent: second call returns existing path without re-creating the disk
    $cidata = New-CidataVhdx -OutputPath 'C:\LabSources\cidata-lin1.vhdx' `
        -Hostname 'LIN1' -Username 'labadmin' -PasswordHash $hash
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Hostname,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Username,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PasswordHash,
        [string]$SSHPublicKey = '',
        [ValidateSet('Ubuntu2404','Ubuntu2204','Rocky9')]
        [string]$Distro = 'Ubuntu2404'
    )

    # Cache: If CIDATA already exists, skip recreation (caller can delete to force rebuild)
    if (Test-Path $OutputPath) {
        Write-LabStatus -Status CACHE -Message "CIDATA VHDX exists, skipping: $OutputPath" -Indent 2
        return $OutputPath
    }

    # Build distro-specific cloud-init user-data
    $ubuntuSshBlock = ''
    if ($SSHPublicKey) {
        $ubuntuSshBlock = @"

    authorized-keys:
      - $SSHPublicKey
"@
    }

    $rockySshBlock = @"
    ssh_authorized_keys: []
"@
    if ($SSHPublicKey) {
        $rockySshBlock = @"
    ssh_authorized_keys:
      - $SSHPublicKey
"@
    }

    switch ($Distro) {
        'Ubuntu2404' {
            $userData = @"
#cloud-config
autoinstall:
  version: 1
  interactive-sections: []
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    version: 2
    ethernets:
      primary:
        match:
          name: "e*"
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
    allow-pw: true$ubuntuSshBlock
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
        }
        'Ubuntu2204' {
            $userData = @"
#cloud-config
# Ubuntu 22.04 compatible autoinstall format
autoinstall:
  version: 1
  interactive-sections: []
  locale: en_US.UTF-8
  keyboard:
    layout: us
  network:
    version: 2
    ethernets:
      primary:
        match:
          name: "e*"
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
    allow-pw: true$ubuntuSshBlock
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
        }
        'Rocky9' {
            $userData = @"
#cloud-config
hostname: $Hostname
users:
  - name: $Username
    lock_passwd: false
    passwd: '$PasswordHash'
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
$rockySshBlock
packages:
  - openssh-server
  - curl
  - wget
  - git
  - net-tools
runcmd:
  - systemctl enable --now sshd
"@
        }
    }

    $metaData = @"
instance-id: iid-$Hostname-$(Get-Date -Format 'yyyyMMddHHmmss')
local-hostname: $Hostname
"@

    # Staging folder for the two files
    $staging = Join-Path $env:TEMP ("cidata-" + [guid]::NewGuid().ToString().Substring(0,8))
    $null = New-Item -ItemType Directory -Path $staging -Force
    Write-Verbose "Created staging directory: $staging"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    try {
        [IO.File]::WriteAllText((Join-Path $staging 'user-data'), $userData, $utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $staging 'meta-data'), $metaData, $utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $staging 'autoinstall'), "", $utf8NoBom)

        # Create parent directory for the VHDX
        $dir = Split-Path $OutputPath -Parent
        if ($dir) {
            $null = New-Item -ItemType Directory -Path $dir -Force
            Write-Verbose "Created directory: $dir"
        }
        if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

        # Create a small dynamic VHDX, partition, format FAT32 with label CIDATA
        Write-Verbose "Creating VHDX: $OutputPath"
        $null = New-VHD -Path $OutputPath -SizeBytes 64MB -Dynamic
        $mounted = Mount-VHD -Path $OutputPath -PassThru
        $diskNum = $mounted.DiskNumber

        Write-Verbose "Initializing disk $diskNum with GPT partition style"
        $null = Initialize-Disk -Number $diskNum -PartitionStyle GPT -PassThru
        $part = New-Partition -DiskNumber $diskNum -UseMaximumSize -AssignDriveLetter
        Write-Verbose "Formatting partition as FAT32 with label CIDATA"
        $null = Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Force

        $driveLetter = ($part | Get-Volume).DriveLetter
        $driveRoot = "${driveLetter}:\"
        Copy-Item (Join-Path $staging 'user-data') (Join-Path $driveRoot 'user-data') -Force
        Copy-Item (Join-Path $staging 'meta-data') (Join-Path $driveRoot 'meta-data') -Force
        Copy-Item (Join-Path $staging 'autoinstall') (Join-Path $driveRoot 'autoinstall') -Force

        Dismount-VHD -Path $OutputPath
        Write-LabStatus -Status OK -Message "CIDATA VHDX created: $OutputPath" -Indent 2
        return $OutputPath
    }
    catch {
        # Ensure VHD is dismounted on failure
        try {
            Dismount-VHD -Path $OutputPath -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "Cleanup dismount failed for '$OutputPath': $($_.Exception.Message)"
        }
        throw
    }
    finally {
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}
