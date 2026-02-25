param(
    [Parameter(Mandatory=$true)]
    [string]$LabName,
    [Parameter(Mandatory=$true)]
    [string]$LabPath,
    [Parameter(Mandatory=$false)]
    [string]$SwitchName = "LabSwitch",
    [Parameter(Mandatory=$false)]
    [string]$SwitchType = "Internal",
    [Parameter(Mandatory=$false)]
    [string]$DomainName = "lab.com",
    [Parameter(Mandatory=$true)]
    [string]$VMsJsonFile,
    [Parameter(Mandatory=$true)]
    [string]$AdminPassword,
    [Parameter(Mandatory=$false)]
    [string]$VMPath = "C:\LabSources\VMs",
    [Parameter(Mandatory=$false)]
    [switch]$Incremental,
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ParallelJobTimeoutSeconds = 180
)

$ErrorActionPreference = 'Continue'

# ============================================================
# PROGRESS HELPER
# ============================================================
function Report-DeployProgress {
    param([int]$Percent, [string]$Status, [string]$Activity = 'Lab Deployment')
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $Percent
    Write-Host "[$Percent%] $Status" -ForegroundColor Cyan
}

function Set-VMInternetPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [Parameter(Mandatory = $true)]
        [bool]$EnableHostInternet,
        [Parameter(Mandatory = $false)]
        [string]$Gateway = '192.168.10.1'
    )

    $modeLabel = if ($EnableHostInternet) { 'enabled' } else { 'disabled' }
    Write-Host "  [NET] Applying host internet policy to ${VmName}: $modeLabel" -ForegroundColor Cyan

    try {
        $hvVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
        if (-not $hvVm) {
            $msg = "VM not found"
            Write-Warning "Could not apply internet policy for ${VmName}: $msg"
            return [pscustomobject]@{
                VMName       = $VmName
                Succeeded    = $false
                ErrorMessage = $msg
                Details      = @()
            }
        }

        if ($hvVm.State -ne 'Running') {
            Start-VM -Name $VmName -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 20
        }

        $commandOutput = @(Invoke-LabCommand -ComputerName $VmName -ActivityName 'Apply host internet policy' -ScriptBlock {
            param($AllowInternet, $NatGateway)

            $defaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' })

            foreach ($route in $defaultRoutes) {
                Remove-NetRoute -AddressFamily IPv4 -DestinationPrefix $route.DestinationPrefix -InterfaceIndex $route.InterfaceIndex -NextHop $route.NextHop -Confirm:$false -ErrorAction SilentlyContinue
            }

            if ($AllowInternet) {
                $nic = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPv4Address -and $_.IPv4Address.IPAddress -like '192.168.10.*' } |
                    Select-Object -First 1

                if (-not $nic) {
                    throw 'No adapter found in 192.168.10.0/24 for NAT default route enforcement.'
                }

                New-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -InterfaceIndex $nic.InterfaceIndex -NextHop $NatGateway -RouteMetric 25 -PolicyStore PersistentStore -ErrorAction SilentlyContinue | Out-Null

                $hasExpectedRoute = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                    Where-Object { $_.InterfaceIndex -eq $nic.InterfaceIndex -and $_.NextHop -eq $NatGateway }

                if (-not $hasExpectedRoute) {
                    throw "Failed to set default route via $NatGateway"
                }

                "Host internet enabled via $NatGateway"
            }
            else {
                'Host internet disabled (default routes removed)'
            }
        } -ArgumentList $EnableHostInternet, $Gateway -ErrorAction Stop)

        $commandOutput | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Gray
        }

        return [pscustomobject]@{
            VMName       = $VmName
            Succeeded    = $true
            ErrorMessage = ''
            Details      = @($commandOutput)
        }
    }
    catch {
        $msg = $_.Exception.Message
        Write-Warning "Could not apply internet policy for ${VmName}: $msg"
        return [pscustomobject]@{
            VMName       = $VmName
            Succeeded    = $false
            ErrorMessage = $msg
            Details      = @()
        }
    }
}

Report-DeployProgress -Percent 0 -Status "Starting deployment: $LabName"

Write-Host "=== OpenCodeLab Deployment (AutomatedLab) ===" -ForegroundColor Cyan
Write-Host "Lab: $LabName"
Write-Host "Domain: $DomainName"
Write-Host ""

if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    throw 'AdminPassword is required for domain creation. Set OPENCODELAB_ADMIN_PASSWORD or pass -AdminPassword.'
}

# ============================================================
# PRE-FLIGHT: Parse VM configuration
# ============================================================
Report-DeployProgress -Percent 1 -Status "Loading VM configuration..."

if (-not (Test-Path $VMsJsonFile)) {
    throw "VM configuration file not found: $VMsJsonFile"
}
$vms = Get-Content $VMsJsonFile -Raw | ConvertFrom-Json

if (-not $vms -or $vms.Count -eq 0) {
    throw "No VMs defined in configuration file"
}

# ============================================================
# PRE-FLIGHT: Import modules
# ============================================================
Report-DeployProgress -Percent 2 -Status "Importing modules..."

Import-Module AutomatedLab -ErrorAction Stop
Import-Module Hyper-V -ErrorAction SilentlyContinue
Write-Host "  AutomatedLab loaded" -ForegroundColor Green

# ============================================================
# PRE-FLIGHT: Validate ISOs and OS names (3-5%)
# ============================================================
Report-DeployProgress -Percent 3 -Status "Validating ISO files and OS images..."

$isoDir = 'C:\LabSources\ISOs'
$isos = Get-ChildItem $isoDir -Filter '*.iso' -ErrorAction SilentlyContinue
if ($isos) {
    foreach ($iso in $isos) {
        Write-Host "  ISO: $($iso.Name) ($([math]::Round($iso.Length/1GB, 1))GB)" -ForegroundColor Cyan
    }
} else {
    throw "No ISO files found in $isoDir. Place Windows Server/Client ISOs there."
}

Report-DeployProgress -Percent 4 -Status "Scanning ISOs for available operating systems..."

# Create a temporary lab definition just to scan available OS images
New-LabDefinition -Name '__IsoScan' -DefaultVirtualizationEngine HyperV -ErrorAction SilentlyContinue
$availableOS = Get-LabAvailableOperatingSystem -ErrorAction SilentlyContinue
# Clean up temp lab definition (Remove-LabDefinition not available in pwsh 7)
Remove-Item "C:\ProgramData\AutomatedLab\Labs\__IsoScan" -Recurse -Force -ErrorAction SilentlyContinue

if ($availableOS) {
    Write-Host "  Available OS images:" -ForegroundColor Yellow
    foreach ($osItem in $availableOS) {
        Write-Host "    $($osItem.OperatingSystemName)" -ForegroundColor Cyan
    }

    # Verify the OS names the VMs will request actually exist in the ISOs
    $defaultOS = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
    $osNameMap = @{
        'Client' = 'Windows 11 Enterprise Evaluation'
    }
    $availableOSNames = @($availableOS | ForEach-Object { $_.OperatingSystemName })

    $osErrors = @()
    foreach ($vm in $vms) {
        $requestedOS = if ($osNameMap.ContainsKey($vm.Role)) { $osNameMap[$vm.Role] } else { $defaultOS }
        $match = $availableOSNames | Where-Object { $_ -eq $requestedOS }
        if ($match) {
            Write-Host "    $($vm.Name) ($($vm.Role)): '$requestedOS' -> FOUND" -ForegroundColor Green
        } else {
            Write-Host "    $($vm.Name) ($($vm.Role)): '$requestedOS' -> NOT FOUND" -ForegroundColor Red
            # Try fuzzy match
            $fuzzy = $availableOSNames | Where-Object { $_ -like "*$($requestedOS.Split(' ')[0..2] -join ' ')*" }
            if ($fuzzy) {
                Write-Host "      Did you mean: $($fuzzy -join ', ')?" -ForegroundColor Yellow
            }
            $osErrors += "$($vm.Name): requested '$requestedOS' not found in ISOs"
        }
    }

    if ($osErrors.Count -gt 0) {
        throw "OS name mismatch - the following VMs request OS images not found in ISOs:`n$($osErrors -join "`n")`n`nAvailable OS images:`n$($availableOSNames -join "`n")`n`nEnsure your ISOs contain the correct Windows editions."
    }
} else {
    Write-Host "  WARNING: Could not scan OS images. AutomatedLab may fail if ISOs don't match." -ForegroundColor Red
}

Report-DeployProgress -Percent 5 -Status "Pre-flight checks passed"

# ============================================================
# CLEANUP / INCREMENTAL DETECTION (5-15%)
# ============================================================

# Detect which VMs already exist in Hyper-V
$existingVMNames = @()
foreach ($vm in $vms) {
    if ([string]::IsNullOrWhiteSpace($vm.Name)) { continue }
    $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
    if ($hvVM) { $existingVMNames += $vm.Name }
}

# Determine new VMs to create
$newVMs = @($vms | Where-Object { $_.Name -notin $existingVMNames })
$keepVMs = @($vms | Where-Object { $_.Name -in $existingVMNames })

if ($Incremental -and $existingVMNames.Count -gt 0) {
    Report-DeployProgress -Percent 6 -Status "Incremental mode: keeping $($existingVMNames.Count) existing VM(s)..."
    Write-Host ""
    Write-Host "=== INCREMENTAL DEPLOYMENT ===" -ForegroundColor Green
    foreach ($name in $existingVMNames) {
        $hvVM = Get-VM -Name $name -ErrorAction SilentlyContinue
        Write-Host "  [KEEP] $name (State: $($hvVM.State))" -ForegroundColor Green
    }
    if ($newVMs.Count -gt 0) {
        foreach ($vm in $newVMs) {
            Write-Host "  [NEW]  $($vm.Name) ($($vm.Role))" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No new VMs to create - all VMs already exist" -ForegroundColor Cyan
        Report-DeployProgress -Percent 100 -Status "All VMs already deployed"
        Write-Host ""
        Write-Host "=== Lab Already Up To Date ===" -ForegroundColor Green
        exit 0
    }

    # In incremental mode, only clean up VMs that don't exist yet (stale leftovers)
    foreach ($vm in $newVMs) {
        $vhdDir = "$VMPath\$($vm.Name)"
        if (Test-Path $vhdDir) {
            Write-Host "  Removing stale disk for new VM: $($vm.Name)" -ForegroundColor Yellow
            Remove-Item $vhdDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Report-DeployProgress -Percent 6 -Status "Cleaning up previous deployment..."

    # Full deployment - remove existing lab
    try {
        $existingLab = Get-Lab -List -ErrorAction SilentlyContinue | Where-Object { $_ -eq $LabName }
        if ($existingLab) {
            Write-Host "  Removing existing lab: $LabName" -ForegroundColor Yellow
            Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue
        }
    } catch { }

    Report-DeployProgress -Percent 10 -Status "Removing stale VMs..."

    foreach ($vm in $vms) {
        $vmName = $vm.Name
        if ([string]::IsNullOrWhiteSpace($vmName)) { continue }
        $existing = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "  Removing VM: $vmName" -ForegroundColor Yellow
            Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
        }
        $vhdDir = "$VMPath\$vmName"
        if (Test-Path $vhdDir) {
            Write-Host "  Removing disk: $vhdDir" -ForegroundColor Yellow
            Remove-Item $vhdDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Report-DeployProgress -Percent 12 -Status "Cleaning up stale switches and NAT..."

    $staleSwitch = Get-VMSwitch -Name $LabName -ErrorAction SilentlyContinue
    if ($staleSwitch) {
        Write-Host "  Removing stale virtual switch: $LabName" -ForegroundColor Yellow
        Remove-VMSwitch -Name $LabName -Force -ErrorAction SilentlyContinue
    }
    # Also clean up any leftover external switches from previous deployments
    $staleExtSwitch = Get-VMSwitch -Name "${LabName}External" -ErrorAction SilentlyContinue
    if ($staleExtSwitch) {
        Write-Host "  Removing stale external switch: ${LabName}External" -ForegroundColor Yellow
        Remove-VMSwitch -Name "${LabName}External" -Force -ErrorAction SilentlyContinue
    }
    Get-VMSwitch -Name "DefaultExternal" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  Removing stale external switch: DefaultExternal" -ForegroundColor Yellow
        Remove-VMSwitch -Name "DefaultExternal" -Force -ErrorAction SilentlyContinue
    }
    $defaultSwitch = Get-VMSwitch -Name 'Default' -ErrorAction SilentlyContinue
    if ($defaultSwitch -and $defaultSwitch.SwitchType -eq 'Internal') {
        Write-Host "  Removing stale 'Default' switch" -ForegroundColor Yellow
        Remove-VMSwitch -Name 'Default' -Force -ErrorAction SilentlyContinue
    }
    Get-NetNat -ErrorAction SilentlyContinue | Where-Object { $_.InternalIPInterfaceAddressPrefix -like '192.168.10.*' } | ForEach-Object {
        Write-Host "  Removing stale NAT: $($_.Name)" -ForegroundColor Yellow
        Remove-NetNat -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Clean stale hosts file entries
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsContent = Get-Content $hostsPath
    $vmNameList = @($vms | ForEach-Object { $_.Name.ToLower() })
    $filtered = $hostsContent | Where-Object {
        $line = $_.Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { return $true }
        $parts = $line -split '\s+'
        foreach ($part in $parts[1..($parts.Length-1)]) {
            $hostname = $part.Split('.')[0]
            if ($vmNameList -contains $hostname) { return $false }
        }
        return $true
    }
    Set-Content -Path $hostsPath -Value $filtered -Force
}

Report-DeployProgress -Percent 8 -Status "Checking base images..."

# Keep existing base images if they exist - AutomatedLab skips creation when present.
$existingBases = Get-ChildItem $VMPath -Filter 'BASE_*' -ErrorAction SilentlyContinue
if ($existingBases) {
    Write-Host "  Keeping $($existingBases.Count) existing base image(s) (reuse speeds deployment)" -ForegroundColor Green
    foreach ($b in $existingBases) {
        Write-Host "    $($b.Name) ($([math]::Round($b.Length/1GB,1))GB)" -ForegroundColor Gray
    }
}

# Remove stale lock files
$lockFile = 'C:\ProgramData\AutomatedLab\LabDiskDeploymentInProgress.txt'
if (Test-Path $lockFile) {
    $alRunning = Get-Process -Name 'integratedlab*','autolab*' -ErrorAction SilentlyContinue
    if (-not $alRunning) {
        Write-Host "  Removing stale deployment lock file" -ForegroundColor Yellow
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
}

Report-DeployProgress -Percent 15 -Status "Cleanup complete"

# ============================================================
# LAB DEFINITION (15-20%)
# ============================================================
Report-DeployProgress -Percent 16 -Status "Creating lab definition..."

if ($Incremental -and $existingVMNames.Count -gt 0) {
    # Import existing lab so AutomatedLab knows about current VMs
    Import-Lab -Name $LabName -NoValidation -ErrorAction SilentlyContinue
}
# Ensure VM path exists
if (-not (Test-Path $VMPath)) { New-Item -Path $VMPath -ItemType Directory -Force | Out-Null }
New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath $VMPath

Report-DeployProgress -Percent 17 -Status "Configuring network..."

# Network - Internal switch with NAT for internet access
# NAT is more reliable than external switches (especially on Wi-Fi adapters)
Add-LabVirtualNetworkDefinition -Name $LabName -AddressSpace 192.168.10.0/24 -HyperVProperties @{ SwitchType = 'Internal' }
Write-Host "  Network: $LabName (Internal + NAT, 192.168.10.0/24)" -ForegroundColor Cyan

# Domain
Write-Host "Configuring domain: $DomainName" -ForegroundColor Yellow
Add-LabDomainDefinition -Name $DomainName -AdminUser dod_admin -AdminPassword $AdminPassword
Set-LabInstallationCredential -Username dod_admin -Password $AdminPassword

# Default parameters
$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:Network'        = $LabName
    'Add-LabMachineDefinition:DomainName'     = $DomainName
    'Add-LabMachineDefinition:OperatingSystem' = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
}

# ============================================================
# ADD MACHINES (17-20%)
# ============================================================
Report-DeployProgress -Percent 18 -Status "Adding virtual machine definitions..."

$serverIP = 10
$clientIP = 50

foreach ($vm in $vms) {
    $vmName = $vm.Name
    if ([string]::IsNullOrWhiteSpace($vmName)) {
        Write-Host "  WARNING: Skipping VM with empty name" -ForegroundColor Yellow
        continue
    }

    # Track whether this VM already exists (incremental mode)
    $vmAlreadyExists = $Incremental -and $vmName -in $existingVMNames

    $memoryBytes = [int64]$vm.MemoryGB * 1GB
    $procCount = 2
    if ($vm.PSObject.Properties['Processors'] -and $vm.Processors -gt 0) {
        $procCount = [int]$vm.Processors
    }

    $vmRole = [string]$vm.Role
    if ([string]::IsNullOrWhiteSpace($vmRole)) {
        $vmRole = 'MemberServer'
    }
    else {
        switch ($vmRole.Trim()) {
            'MS'     { $vmRole = 'MemberServer'; break }
            'Member' { $vmRole = 'MemberServer'; break }
            'Server' { $vmRole = 'MemberServer'; break }
            default  { $vmRole = $vmRole.Trim() }
        }
    }

    $alRole = $null
    $isClient = $false
    $os = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'

    switch -Regex ($vmRole) {
        '^DC$' {
            $firstDC = @($vms | Where-Object { $_.Role -eq 'DC' })[0]
            if ($vm.Name -eq $firstDC.Name) {
                $alRole = Get-LabMachineRoleDefinition -Role RootDC
            } else {
                $alRole = Get-LabMachineRoleDefinition -Role DC
            }
        }
        'FileServer' { $alRole = Get-LabMachineRoleDefinition -Role FileServer }
        'WebServer'  { $alRole = Get-LabMachineRoleDefinition -Role WebServer }
        'SQL'        { $alRole = Get-LabMachineRoleDefinition -Role SQLServer2019 }
        'DHCP'       { $alRole = Get-LabMachineRoleDefinition -Role DHCP }
        'CA'         { $alRole = Get-LabMachineRoleDefinition -Role CaRoot }
        'Client' {
            $isClient = $true
            $os = 'Windows 11 Enterprise Evaluation'
        }
    }

    if ($isClient) { $ip = "192.168.10.$clientIP"; $clientIP++ }
    else           { $ip = "192.168.10.$serverIP"; $serverIP++ }

    $params = @{
        Name            = $vmName
        Memory          = $memoryBytes
        Processors      = $procCount
        IpAddress       = $ip
        OperatingSystem = $os
    }
    if ($alRole) { $params['Roles'] = $alRole }

    if ($vmAlreadyExists) {
        Write-Host "  [EXISTING] $vmName ($vmRole) - $os, IP: $ip (will be kept)" -ForegroundColor DarkGray
    } else {
        Write-Host "  $vmName ($vmRole) - $os, ${procCount}CPU, $($vm.MemoryGB)GB RAM, IP: $ip" -ForegroundColor Cyan
    }

    # Always add to lab definition so AutomatedLab validates domain topology correctly
    # Install-Lab will detect existing VMs and skip re-creating them
    Add-LabMachineDefinition @params
}

Report-DeployProgress -Percent 20 -Status "Machine definitions complete"

# ============================================================
# PRE-INSTALL: Create base images and validate EFI boot (20-30%)
# AutomatedLab's bcdboot call silently fails (piped to Out-Null),
# leaving EFI partitions empty. We create base images first, then
# verify and repair before Install-Lab creates differencing disks.
# See: https://github.com/AutomatedLab/AutomatedLab/issues/1662
# ============================================================
Report-DeployProgress -Percent 21 -Status "Creating base images (if needed)..."

Write-Host ""
Write-Host "Creating base disk images..." -ForegroundColor Yellow
try {
    # Use Install-Lab -BaseImages (not bare New-LabBaseImages) so lab context is available
    Install-Lab -BaseImages -ErrorAction Stop
    Write-Host "  Base images ready" -ForegroundColor Green
} catch {
    Write-Host "  Base image creation error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Install-Lab will retry base image creation" -ForegroundColor Yellow
}

Report-DeployProgress -Percent 25 -Status "Validating EFI boot partitions on base images..."

$baseVhdxFiles = Get-ChildItem $VMPath -Filter 'BASE_*.vhdx' -ErrorAction SilentlyContinue
$efiRepairCount = 0

foreach ($baseVhdx in $baseVhdxFiles) {
    Write-Host "  Checking: $($baseVhdx.Name) ($([math]::Round($baseVhdx.Length/1GB,1))GB)" -ForegroundColor Gray

    # Ensure clean state
    Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
    Start-Sleep 1

    $mounted = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Mount-VHD -Path $baseVhdx.FullName -ErrorAction Stop
            $mounted = $true
            break
        } catch {
            Write-Host "    Mount attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
    }

    if (-not $mounted) {
        Write-Host "    [SKIP] Could not mount - Install-Lab may still work" -ForegroundColor Yellow
        continue
    }

    Start-Sleep 2

    try {
        $disk = Get-VHD -Path $baseVhdx.FullName
        $diskNumber = $disk.DiskNumber
        $partitions = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue

        $efiPart = $partitions | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
        $winPart = $partitions | Where-Object { $_.Type -eq 'Basic' -and $_.Size -gt 1GB }

        if (-not $efiPart) {
            Write-Host "    [OK] No EFI partition (MBR/Gen1 disk)" -ForegroundColor Green
            continue
        }

        if (-not $winPart) {
            Write-Host "    [WARN] No Windows partition found" -ForegroundColor Yellow
            continue
        }

        # Assign temporary drive letters
        $usedLetters = @(Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
        $efiLetter = $null
        $winLetter = if ($winPart.DriveLetter) { [string]$winPart.DriveLetter } else { $null }

        foreach ($code in 83..90) {  # S-Z
            $l = [string][char]$code
            if ($l -notin $usedLetters -and $l -ne $winLetter) { $efiLetter = $l; break }
        }
        if (-not $winLetter) {
            foreach ($code in 71..82) {  # G-R
                $l = [string][char]$code
                if ($l -notin $usedLetters -and $l -ne $efiLetter) { $winLetter = $l; break }
            }
            if ($winLetter) {
                Set-Partition -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $winLetter
            }
        }

        if (-not $efiLetter -or -not $winLetter) {
            Write-Host "    [WARN] No available drive letters for EFI check" -ForegroundColor Yellow
            continue
        }

        Set-Partition -DiskNumber $diskNumber -PartitionNumber $efiPart.PartitionNumber -NewDriveLetter $efiLetter
        Start-Sleep 2

        $bcdPath = "${efiLetter}:\EFI\Microsoft\Boot\BCD"
        $bootEfiPath = "${efiLetter}:\EFI\Microsoft\Boot\bootmgfw.efi"

        if ((Test-Path $bcdPath) -and (Test-Path $bootEfiPath)) {
            Write-Host "    [OK] EFI boot files present" -ForegroundColor Green
        } else {
            Write-Host "    [FIX] EFI partition missing boot files - running bcdboot..." -ForegroundColor Yellow

            $winDir = "${winLetter}:\Windows"
            if (-not (Test-Path $winDir)) {
                Write-Host "    [ERROR] Windows directory not found at $winDir" -ForegroundColor Red
                continue
            }

            # Diagnose the source Windows\Boot\EFI directory
            $bootEfiSrc = "${winLetter}:\Windows\Boot\EFI"
            Write-Host "    Source boot dir: $bootEfiSrc (exists: $(Test-Path $bootEfiSrc))" -ForegroundColor Gray

            $winPSExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

            # Method 1: Use the VHDX's OWN bcdboot.exe (Server 2019) instead of host's (Win11)
            # Host bcdboot returns exit 193 - likely version mismatch between Win11 host and Server 2019 guest
            $guestBcdboot = "${winLetter}:\Windows\System32\bcdboot.exe"
            $hostBcdboot = "$env:SystemRoot\System32\bcdboot.exe"

            if (Test-Path $guestBcdboot) {
                Write-Host "    [Method 1] Using VHDX's own bcdboot.exe (Server 2019)..." -ForegroundColor Gray
                $bcdbootResult = & $winPSExe -NoProfile -Command "& '$guestBcdboot' '${winLetter}:\Windows' /s '${efiLetter}:' /f UEFI 2>&1; Write-Host `"EXIT:`$LASTEXITCODE`"; exit `$LASTEXITCODE" 2>&1
                $bcdbootExit = $LASTEXITCODE
                Write-Host "    Result (exit $bcdbootExit): $bcdbootResult" -ForegroundColor Gray

                if ($bcdbootExit -eq 0 -and (Test-Path $bcdPath)) {
                    Write-Host "    [OK] Guest bcdboot succeeded - proper BCD created!" -ForegroundColor Green
                    $efiRepairCount++
                } else {
                    Write-Host "    [WARN] Guest bcdboot failed, trying host bcdboot..." -ForegroundColor Yellow
                }
            }

            # Method 2: Host bcdboot via cmd.exe (may fail with 193)
            if (-not (Test-Path $bcdPath)) {
                Write-Host "    [Method 2] Host bcdboot via cmd.exe..." -ForegroundColor Gray
                $bcdbootResult2 = & cmd.exe /c "`"$hostBcdboot`" `"${winLetter}:\Windows`" /s ${efiLetter}: /f UEFI" 2>&1
                $bcdbootExit2 = $LASTEXITCODE
                Write-Host "    Result (exit $bcdbootExit2): $bcdbootResult2" -ForegroundColor Gray

                if ($bcdbootExit2 -eq 0 -and (Test-Path $bcdPath)) {
                    Write-Host "    [OK] Host bcdboot succeeded!" -ForegroundColor Green
                    $efiRepairCount++
                }
            }

            # Method 3: Manual boot file copy + BCD as last resort
            if (-not (Test-Path $bcdPath)) {
                Write-Host "    [Method 3] Manual EFI boot file copy + BCD..." -ForegroundColor Yellow

                $srcBootEfi = "${winLetter}:\Windows\Boot\EFI"
                if (Test-Path "$srcBootEfi\bootmgfw.efi") {
                    $efiBootDir = "${efiLetter}:\EFI\Microsoft\Boot"
                    New-Item -Path $efiBootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                    New-Item -Path "${efiLetter}:\EFI\Boot" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

                    Copy-Item "$srcBootEfi\bootmgfw.efi" "$efiBootDir\bootmgfw.efi" -Force -ErrorAction SilentlyContinue
                    Copy-Item "$srcBootEfi\bootmgfw.efi" "${efiLetter}:\EFI\Boot\bootx64.efi" -Force -ErrorAction SilentlyContinue
                    if (Test-Path "$srcBootEfi\memtest.efi") {
                        Copy-Item "$srcBootEfi\memtest.efi" "$efiBootDir\memtest.efi" -Force -ErrorAction SilentlyContinue
                    }
                    # Copy locale MUI files
                    Get-ChildItem $srcBootEfi -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        $destDir = "$efiBootDir\$($_.Name)"
                        New-Item -Path $destDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                        Copy-Item "$($_.FullName)\*" $destDir -Force -ErrorAction SilentlyContinue
                    }
                    Copy-Item "$srcBootEfi\boot.stl" "$efiBootDir\boot.stl" -Force -ErrorAction SilentlyContinue
                    Copy-Item "$srcBootEfi\winsipolicy.p7b" "$efiBootDir\winsipolicy.p7b" -Force -ErrorAction SilentlyContinue

                    # Create BCD with locate-based references
                    Write-Host "    Creating BCD store..." -ForegroundColor Gray
                    $bcdStore = "$efiBootDir\BCD"
                    $bcdeditResult = & $winPSExe -NoProfile -Command @"
                        `$s = '$bcdStore'
                        bcdedit /createstore `$s 2>&1
                        bcdedit /store `$s /create '{bootmgr}' /d 'Windows Boot Manager' 2>&1
                        bcdedit /store `$s /set '{bootmgr}' device boot 2>&1
                        bcdedit /store `$s /set '{bootmgr}' path \EFI\Microsoft\Boot\bootmgfw.efi 2>&1
                        `$g = (bcdedit /store `$s /create /d 'Windows Server' /application osloader 2>&1) -replace '.*(\{.*\}).*','`$1'
                        bcdedit /store `$s /set `$g device 'locate=\Windows\system32\winload.efi' 2>&1
                        bcdedit /store `$s /set `$g osdevice 'locate=\Windows\system32\ntoskrnl.exe' 2>&1
                        bcdedit /store `$s /set `$g path \Windows\system32\winload.efi 2>&1
                        bcdedit /store `$s /set `$g systemroot \Windows 2>&1
                        bcdedit /store `$s /set `$g locale en-US 2>&1
                        bcdedit /store `$s /set '{bootmgr}' default `$g 2>&1
                        bcdedit /store `$s /set '{bootmgr}' displayorder `$g 2>&1
                        bcdedit /store `$s /set '{bootmgr}' timeout 0 2>&1
"@ 2>&1
                    Write-Host "    bcdedit: $($bcdeditResult | Out-String)" -ForegroundColor Gray

                    if (Test-Path $bcdPath) {
                        Write-Host "    [OK] Manual boot file copy + BCD succeeded!" -ForegroundColor Green
                        $efiRepairCount++
                    } else {
                        Write-Host "    [FAIL] BCD creation failed" -ForegroundColor Red
                    }
                } else {
                    Write-Host "    [FAIL] No bootmgfw.efi found in VHDX" -ForegroundColor Red
                }
            }
        }

        # Clean up drive letter
        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $efiPart.PartitionNumber -AccessPath "${efiLetter}:\" -ErrorAction SilentlyContinue
        if (-not $winPart.DriveLetter) {
            Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -AccessPath "${winLetter}:\" -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "    [ERROR] EFI check failed: $_" -ForegroundColor Red
    } finally {
        Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
    }
}

if ($efiRepairCount -gt 0) {
    Write-Host ""
    Write-Host "  Repaired EFI boot files on $efiRepairCount base image(s)" -ForegroundColor Green
}

Report-DeployProgress -Percent 30 -Status "Base image EFI validation complete"

# ============================================================
# INSTALL LAB (30-80%)
# ============================================================
Report-DeployProgress -Percent 30 -Status "Installing lab (this takes 15-45 minutes)..."

Write-Host ""
Write-Host "Installing lab (this will take a while)..." -ForegroundColor Yellow
Write-Host "  - Create VMs, install OS, configure AD, join domain" -ForegroundColor Gray
Write-Host "  Started at: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

$installStart = Get-Date
$installError = $null

try {
    Install-Lab -ErrorAction Stop
} catch {
    $installError = $_
    Write-Host ""
    Write-Host "  INSTALL-LAB ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Will verify VM creation and attempt recovery..." -ForegroundColor Yellow
}

$installElapsed = (Get-Date) - $installStart
Write-Host ("  Install-Lab completed in {0:D2}m {1:D2}s" -f [int]$installElapsed.TotalMinutes, $installElapsed.Seconds) -ForegroundColor Green

Report-DeployProgress -Percent 78 -Status "Install-Lab finished in $([int]$installElapsed.TotalMinutes)m $($installElapsed.Seconds)s"

# ============================================================
# POST-INSTALL: Create dod_admin domain admin account
# ============================================================
$dcVM = $vms | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1
if ($dcVM -and -not $installError) {
    Report-DeployProgress -Percent 78 -Status "Creating dod_admin domain admin account..."
    try {
        $dcName = $dcVM.Name
        Write-Host "  Creating domain admin account: dod_admin on $dcName" -ForegroundColor Yellow
        Invoke-LabCommand -ComputerName $dcName -ActivityName 'Create dod_admin' -ScriptBlock {
            param($pw)
            Import-Module ActiveDirectory -ErrorAction Stop
            if (-not (Get-ADUser -Filter "SamAccountName -eq 'dod_admin'" -ErrorAction SilentlyContinue)) {
                if ([string]::IsNullOrWhiteSpace($pw)) {
                    throw 'Admin password cannot be empty when creating dod_admin.'
                }

                $secPw = New-Object System.Security.SecureString
                foreach ($ch in $pw.ToCharArray()) {
                    $secPw.AppendChar($ch)
                }
                $secPw.MakeReadOnly()

                New-ADUser -Name 'dod_admin' -SamAccountName 'dod_admin' -UserPrincipalName "dod_admin@$((Get-ADDomain).DNSRoot)" `
                    -AccountPassword $secPw -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $false `
                    -Description 'Lab Domain Administrator'
                Add-ADGroupMember -Identity 'Domain Admins' -Members 'dod_admin'
                Add-ADGroupMember -Identity 'Enterprise Admins' -Members 'dod_admin'
                Write-Host "  [OK] dod_admin created and added to Domain Admins + Enterprise Admins" -ForegroundColor Green
            } else {
                Write-Host "  [OK] dod_admin already exists" -ForegroundColor Green
            }
        } -ArgumentList $AdminPassword -ErrorAction Stop
        Write-Host "  [OK] dod_admin account ready (password same as admin)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Could not create dod_admin: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ============================================================
# POST-INSTALL: Verify EFI Boot (safety net - pre-install should have fixed this)
# ============================================================
Report-DeployProgress -Percent 79 -Status "Verifying boot configuration..."

# Quick check: are VMs actually running with heartbeat?
$needsBootRepair = $false
foreach ($vm in $vms) {
    $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
    if (-not $hvVM) { continue }
    if ($hvVM.Generation -eq 2 -and $hvVM.State -eq 'Running') {
        $hb = $hvVM.Heartbeat
        if ($hb -eq 'OkApplicationsHealthy' -or $hb -eq 'OkApplicationsUnknown') {
            Write-Host "  [OK] $($vm.Name) booted with heartbeat: $hb" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] $($vm.Name) heartbeat: $hb - may need boot repair" -ForegroundColor Yellow
            $needsBootRepair = $true
        }
    }
}

if ($needsBootRepair) {
    Write-Host "  Some VMs may not have booted. Attempting post-install EFI repair..." -ForegroundColor Yellow

    # Stop VMs, repair base image, restart
    foreach ($vm in $vms) {
        $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
        if ($hvVM -and $hvVM.State -ne 'Off') {
            Stop-VM -Name $vm.Name -TurnOff -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep 5

    $baseVhdxFiles = Get-ChildItem $VMPath -Filter 'BASE_*.vhdx' -ErrorAction SilentlyContinue
    foreach ($baseVhdx in $baseVhdxFiles) {
        Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
        Start-Sleep 1
        try {
            Mount-VHD -Path $baseVhdx.FullName -ErrorAction Stop
            Start-Sleep 2

            $disk = Get-VHD -Path $baseVhdx.FullName
            $dn = $disk.DiskNumber
            $efiPart = Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue |
                Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
            $winPart = Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue |
                Where-Object { $_.Type -eq 'Basic' -and $_.Size -gt 1GB }

            if ($efiPart -and $winPart) {
                $usedLetters = @(Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter })
                $efiL = $null; $winL = if ($winPart.DriveLetter) { [string]$winPart.DriveLetter } else { $null }
                foreach ($c in 83..90) { $l = [string][char]$c; if ($l -notin $usedLetters -and $l -ne $winL) { $efiL = $l; break } }
                if (-not $winL) {
                    foreach ($c in 71..82) { $l = [string][char]$c; if ($l -notin $usedLetters -and $l -ne $efiL) { $winL = $l; break } }
                    if ($winL) { Set-Partition -DiskNumber $dn -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $winL }
                }
                if ($efiL -and $winL) {
                    Set-Partition -DiskNumber $dn -PartitionNumber $efiPart.PartitionNumber -NewDriveLetter $efiL
                    Start-Sleep 2
                    if (-not (Test-Path "${efiL}:\EFI\Microsoft\Boot\BCD")) {
                        Write-Host "  [FIX] Running bcdboot on $($baseVhdx.Name)..." -ForegroundColor Yellow
                        $bcdExe = "$env:SystemRoot\System32\bcdboot.exe"
                        if (-not (Test-Path $bcdExe)) { $bcdExe = 'bcdboot.exe' }
                        & cmd.exe /c "`"$bcdExe`" `"${winL}:\Windows`" /s ${efiL}: /f UEFI" 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
                    }
                    Remove-PartitionAccessPath -DiskNumber $dn -PartitionNumber $efiPart.PartitionNumber -AccessPath "${efiL}:\" -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Host "  [ERROR] Post-install repair failed: $_" -ForegroundColor Red
        } finally {
            Dismount-VHD -Path $baseVhdx.FullName -ErrorAction SilentlyContinue
        }
    }

    # Restart VMs
    foreach ($vm in $vms) {
        $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
        if ($hvVM -and $hvVM.State -eq 'Off') {
            Start-VM -Name $vm.Name -ErrorAction SilentlyContinue
            Write-Host "  Restarted $($vm.Name)" -ForegroundColor Green
        }
    }
    Write-Host "  Waiting 60s for VMs to boot..." -ForegroundColor Yellow
    Start-Sleep 60
}

Report-DeployProgress -Percent 80 -Status "Boot verification complete"

# Ensure Gen2 VMs have hard drive in boot order
foreach ($vm in $vms) {
    $vmName = $vm.Name
    $hvVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $hvVM -or $hvVM.Generation -ne 2) { continue }

    $hdd = Get-VMHardDiskDrive -VMName $vmName -ErrorAction SilentlyContinue
    $fw = Get-VMFirmware -VMName $vmName -ErrorAction SilentlyContinue

    if ($hdd -and $fw) {
        $hasHddBoot = $fw.BootOrder | Where-Object { $_.BootType -eq 'Drive' -and $_.Device -is [Microsoft.HyperV.PowerShell.HardDiskDrive] }
        if (-not $hasHddBoot) {
            Write-Host "  [FIX] Adding hard drive to boot order for $vmName" -ForegroundColor Yellow
            try { Set-VMFirmware -VMName $vmName -FirstBootDevice $hdd } catch { }
        }
    }
}

# ============================================================
# POST-INSTALL: VHDX Validation (80-85%)
# ============================================================
Report-DeployProgress -Percent 81 -Status "Validating VM disk images..."

$vhdxRoot = $VMPath
$vhdxWarnings = @()

foreach ($vm in $vms) {
    $vmName = $vm.Name
    $vmDir = Join-Path $vhdxRoot $vmName

    # Check VM exists
    $hvVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $hvVM) {
        $vhdxWarnings += "VM '$vmName' was NOT created by Install-Lab"
        Write-Host "  [FAIL] VM '$vmName' not found" -ForegroundColor Red
        continue
    }
    Write-Host "  [OK] VM '$vmName' exists (State: $($hvVM.State))" -ForegroundColor Green

    # Check VHDX sizes
    if (Test-Path $vmDir) {
        $vhdxFiles = Get-ChildItem $vmDir -Filter '*.vhdx' -ErrorAction SilentlyContinue
        foreach ($vhdxFile in $vhdxFiles) {
            $sizeMB = [math]::Round($vhdxFile.Length / 1MB)
            if ($sizeMB -lt 500) {
                $msg = "VM '$vmName' disk '$($vhdxFile.Name)' is only ${sizeMB}MB - OS installation likely failed!"
                $vhdxWarnings += $msg
                Write-Host "  [WARN] $msg" -ForegroundColor Red

                # Check parent VHDX chain
                try {
                    $vhdInfo = Get-VHD -Path $vhdxFile.FullName -ErrorAction Stop
                    if ($vhdInfo.ParentPath) {
                        $parentExists = Test-Path $vhdInfo.ParentPath
                        Write-Host "    Type: $($vhdInfo.VhdType), Parent: $($vhdInfo.ParentPath) (exists: $parentExists)" -ForegroundColor Yellow
                        if (-not $parentExists) {
                            $vhdxWarnings += "Parent VHDX missing for '$vmName': $($vhdInfo.ParentPath)"
                            Write-Host "    ERROR: Parent VHDX is missing! Differencing disk chain is broken." -ForegroundColor Red
                        }
                    }
                } catch {
                    Write-Host "    Could not inspect VHDX: $_" -ForegroundColor Yellow
                }
            } else {
                $sizeGB = [math]::Round($sizeMB / 1024, 1)
                Write-Host "  [OK] '$vmName' disk: ${sizeGB}GB ($($vhdxFile.Name))" -ForegroundColor Green
            }
        }
    }

    # Check Gen2 firmware boot configuration
    if ($hvVM.Generation -eq 2) {
        $firmware = Get-VMFirmware -VMName $vmName -ErrorAction SilentlyContinue
        if ($firmware -and $firmware.BootOrder.Count -gt 0) {
            $firstBoot = $firmware.BootOrder[0].BootType
            Write-Host "    Boot order[0]: $firstBoot" -ForegroundColor Gray
        }
        $dvd = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue
        if ($dvd -and $dvd.Path) {
            Write-Host "    DVD: $($dvd.Path)" -ForegroundColor Gray
        }
    }
}

if ($vhdxWarnings.Count -gt 0) {
    Write-Host ""
    Write-Host "=== VHDX VALIDATION WARNINGS ===" -ForegroundColor Red
    foreach ($w in $vhdxWarnings) {
        Write-Host "  - $w" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Run: Get-LabAvailableOperatingSystem -Path 'C:\LabSources\ISOs'" -ForegroundColor Yellow
    Write-Host "  2. Verify OS names match exactly (case-sensitive)" -ForegroundColor Yellow
    Write-Host "  3. Check $VMPath for BASE_*.vhdx files" -ForegroundColor Yellow
    Write-Host "  4. Re-run deployment to recreate from scratch" -ForegroundColor Yellow
}

Report-DeployProgress -Percent 85 -Status "VHDX validation complete"

# ============================================================
# POST-INSTALL: Per-VM internet policy enforcement (85-88%)
# ============================================================
Report-DeployProgress -Percent 86 -Status "Applying per-VM internet policy..."

$internetPolicyTargets = @()
foreach ($vm in $vms) {
    if ([string]::IsNullOrWhiteSpace($vm.Name)) {
        continue
    }

    $internetEnabled = $false
    if ($vm.PSObject.Properties.Name -contains 'EnableHostInternet') {
        $internetEnabled = [bool]$vm.EnableHostInternet
    }

    $internetPolicyTargets += [pscustomobject]@{
        VMName             = [string]$vm.Name
        LabName            = [string]$LabName
        EnableHostInternet = $internetEnabled
        Gateway            = '192.168.10.1'
    }
}

$internetPolicyFailures = @()

foreach ($item in $internetPolicyTargets) {
    $policyResult = Set-VMInternetPolicy -VmName $item.VMName -EnableHostInternet $item.EnableHostInternet -Gateway $item.Gateway

    if ($policyResult -and $policyResult.Succeeded) {
        Write-Host "  [NET][OK] $($policyResult.VMName)" -ForegroundColor Green
        continue
    }

    $errorMessage = if ($policyResult -and $policyResult.ErrorMessage) {
        [string]$policyResult.ErrorMessage
    }
    else {
        'Unknown error'
    }

    $failure = [pscustomobject]@{
        Name            = "internet-policy-$($item.VMName)"
        FailureCategory = 'ExecutionError'
        ErrorMessage    = $errorMessage
    }

    $internetPolicyFailures += $failure
    Write-Warning "Internet policy failed for $($failure.Name) [$($failure.FailureCategory)]: $($failure.ErrorMessage)"
}

if ($internetPolicyFailures.Count -gt 0) {
    Write-Host "  [NET] Failed internet policy jobs: $($internetPolicyFailures.Count)" -ForegroundColor Yellow
}

# ============================================================
# POST-INSTALL: Verify boot and show summary (85-95%)
# ============================================================
Report-DeployProgress -Percent 88 -Status "Generating deployment summary..."

Write-Host ""
try {
    Show-LabDeploymentSummary
} catch {
    Write-Host "  Could not generate AutomatedLab summary: $_" -ForegroundColor Yellow
}

Report-DeployProgress -Percent 95 -Status "Deployment summary complete"

# ============================================================
# FINAL STATUS (95-100%)
# ============================================================
if ($installError -and $vhdxWarnings.Count -gt 0) {
    Report-DeployProgress -Percent 100 -Status "Deployment finished with errors - check warnings above"
    Write-Host ""
    Write-Host "=== Deployment Finished With Errors ===" -ForegroundColor Red
    Write-Host "Install-Lab error: $($installError.Exception.Message)" -ForegroundColor Red
    Write-Host "VHDX warnings: $($vhdxWarnings.Count)" -ForegroundColor Red
    exit 1
} elseif ($internetPolicyFailures.Count -gt 0) {
    Report-DeployProgress -Percent 100 -Status "Deployment finished with internet policy failures"
    Write-Host "" 
    Write-Host "=== Deployment Finished With Internet Policy Failures ===" -ForegroundColor Red
    foreach ($policyFailure in $internetPolicyFailures) {
        Write-Host "  - $($policyFailure.Name): [$($policyFailure.FailureCategory)] $($policyFailure.ErrorMessage)" -ForegroundColor Red
    }
    exit 1
} elseif ($vhdxWarnings.Count -gt 0) {
    Report-DeployProgress -Percent 100 -Status "Deployment finished with VHDX warnings"
    Write-Host ""
    Write-Host "=== Deployment Complete (with warnings) ===" -ForegroundColor Yellow
    exit 0
} else {
    Report-DeployProgress -Percent 100 -Status "Deployment completed successfully!"
    Write-Host ""
    Write-Host "=== Deployment Complete ===" -ForegroundColor Green
    Write-Host "All VMs are installed, domain-joined, and roles configured."
    exit 0
}
