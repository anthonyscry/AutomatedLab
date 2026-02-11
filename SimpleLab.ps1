# SimpleLab.ps1
# SimpleLab v4.0.1 - Windows Domain Lab Automation with DSC Pull Server
# Uses AutomatedLab module for complete automation

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Build', 'Start', 'Stop', 'Restart', 'Suspend', 'Status', 'Checkpoint', 'Reset', 'NAT', 'SSHKey', 'Preflight', 'DSCStatus', 'Menu', 'Help')]
    [string]$Operation = 'Menu'
)

# Exit codes
$EXIT_SUCCESS = 0
$EXIT_ERROR = 1
$EXIT_VALIDATION = 2
$EXIT_CANCELLED = 3

$ErrorActionPreference = 'Stop'
$script:exitCode = $EXIT_SUCCESS

# ============================================================
# LAB CONFIGURATION
# ============================================================
$LabName = 'SimpleLab'
$DomainName = 'simplelab.local'
$LabVMs = @('dc1', 'svr1', 'dsc', 'ws1')

# Networking
$LabSwitch = 'SimpleLab'
$AddressSpace = '10.0.10.0/24'
$GatewayIp = '10.0.10.1'
$NatName = "${LabSwitch}NAT"

# IP Addresses
$dc1_Ip   = '10.0.10.10'
$svr1_Ip  = '10.0.10.20'
$dsc_Ip   = '10.0.10.40'
$ws1_Ip   = '10.0.10.30'
$DnsIp    = $dc1_Ip

# Paths
$LabPath = "C:\AutomatedLab\$LabName"
$LabSourcesRoot = 'C:\LabSources'
$IsoPath = Join-Path $LabSourcesRoot 'ISOs'

# Credentials
$LabInstallUser = 'Administrator'
$AdminPassword = 'SimpleLab123!'

# Memory (dynamic)
$DC_Memory      = 4GB
$DC_MinMemory   = 2GB
$DC_MaxMemory   = 6GB
$Server_Memory  = 4GB
$Server_MinMemory = 2GB
$Server_MaxMemory = 6GB
$Client_Memory  = 4GB
$Client_MinMemory = 2GB
$Client_MaxMemory = 6GB
$DSC_Memory     = 4GB
$DSC_MinMemory  = 2GB
$DSC_MaxMemory  = 6GB
$Processors = 4

# Required ISOs
$RequiredISOs = @('server2019.iso', 'windows11.iso')

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Import-AutomatedLabModule {
    try {
        if (-not (Get-Module -ListAvailable -Name AutomatedLab -ErrorAction SilentlyContinue)) {
            throw "AutomatedLab module not installed. Run: Install-Module AutomatedLab -Force -Scope CurrentUser"
        }
        Import-Module AutomatedLab -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "Failed to import AutomatedLab module: $($_.Exception.Message)"
        return $false
    }
}

function Remove-HyperVVMStale {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter()][string]$Context = 'cleanup',
        [Parameter()][int]$MaxAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vm) { return $true }

        Write-Host "    [WARN] Found VM '$VMName' during $Context (attempt $attempt/$MaxAttempts). Removing..." -ForegroundColor Yellow

        Hyper-V\Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMSnapshot -ErrorAction SilentlyContinue | Out-Null

        Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue |
            Hyper-V\Remove-VMDvdDrive -ErrorAction SilentlyContinue | Out-Null

        if ($vm.State -like 'Saved*') {
            Hyper-V\Remove-VMSavedState -VMName $VMName -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 1
            $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        }

        if ($vm -and $vm.State -ne 'Off') {
            Hyper-V\Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 2
        }

        Hyper-V\Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $stillThere = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $stillThere) {
            Write-Host "    [OK] Removed VM '$VMName'" -ForegroundColor Green
            return $true
        }

        $vmId = $stillThere.VMId.Guid
        $vmwp = Get-CimInstance Win32_Process -Filter "Name='vmwp.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$vmId*" } |
            Select-Object -First 1
        if ($vmwp) {
            Stop-Process -Id $vmwp.ProcessId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }

    return -not (Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue)
}

function Show-Banner {
    Write-Host ""
    Write-Host "SimpleLab v4.0.1 - Windows Domain Lab + DSC Pull Server" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Gray
    Write-Host ""
}

function Show-LabStatusHeader {
    $status = Get-LabStatus -ErrorAction SilentlyContinue

    Write-Host "Current Lab Status:" -ForegroundColor White

    if ($null -eq $status -or $status.Count -eq 0) {
        Write-Host "  No lab VMs found" -ForegroundColor Gray
    }
    else {
        foreach ($vm in $status) {
            $statusColor = switch ($vm.State) {
                "Running"   { "Green" }
                "Off"       { "Gray" }
                "Saved"     { "Yellow" }
                default     { "Yellow" }
            }

            Write-Host "  $($vm.VMName.PadRight(15)) " -NoNewline -ForegroundColor Cyan
            Write-Host ($vm.State.PadRight(12)) -NoNewline -ForegroundColor $statusColor
            Write-Host ""
        }
    }
    Write-Host ""
}

function Show-Menu {
    Show-Banner
    Show-LabStatusHeader

    Write-Host "Main Menu:" -ForegroundColor White
    Write-Host "  1. Build Lab        - Create VMs, configure domain, create LabReady checkpoint"
    Write-Host "  2. Start Lab        - Start all lab VMs"
    Write-Host "  3. Stop Lab         - Stop all lab VMs"
    Write-Host "  4. Restart Lab      - Restart all lab VMs"
    Write-Host "  5. Suspend Lab      - Suspend all lab VMs (save state)"
    Write-Host "  6. Show Status      - Display detailed lab status"
    Write-Host "  7. LabReady Checkpoint - Create baseline checkpoint"
    Write-Host "  8. Restore Checkpoint - Restore from a previous checkpoint"
    Write-Host "  9. Setup NAT        - Create NAT network (for Internet access)"
    Write-Host "  D. DSC Status       - Show DSC Pull Server status"
    Write-Host "  R. Reset Lab        - Complete lab teardown (remove VMs, checkpoints, vSwitch)"
    Write-Host "  0. Exit             - Exit SimpleLab"
    Write-Host ""

    $selection = Read-Host "Select option"
    return $selection
}

function Invoke-MenuOperation {
    param([string]$Selection)

    # Normalize to uppercase and handle both cases
    $Selection = $Selection.ToUpper()

    switch -Exact ($Selection) {
        "1" { Invoke-BuildLab }
        "2" { Invoke-StartLab }
        "3" { Invoke-StopLab }
        "4" { Invoke-RestartLab }
        "5" { Invoke-SuspendLab }
        "6" { Invoke-ShowStatus }
        "7" { Invoke-CreateCheckpoint }
        "8" { Invoke-RestoreCheckpointMenu }
        "9" { Invoke-SetupNAT }
        "D" { Invoke-DSCStatus }
        "R" { Invoke-ResetLab }
        "0" { return $false }
        default {
            Write-Host "Invalid option. Please select 0-9, D, or R." -ForegroundColor Red
            pause
            return $true
        }
    }
    return $true
}

function Invoke-BuildLab {
    Write-Host ""
    Write-Host "=== Building Lab with AutomatedLab ===" -ForegroundColor Cyan

    # Check for AutomatedLab module
    Write-Host "Checking for AutomatedLab module..." -ForegroundColor Yellow
    if (-not (Get-Module -ListAvailable -Name AutomatedLab -ErrorAction SilentlyContinue)) {
        Write-Host "  [ERROR] AutomatedLab module not installed." -ForegroundColor Red
        Write-Host "  Install with: Install-Module AutomatedLab -Force -Scope CurrentUser" -ForegroundColor Yellow
        pause
        return
    }
    Write-Host "  [OK] AutomatedLab module found" -ForegroundColor Green

    # Check ISOs
    Write-Host "Checking ISOs..." -ForegroundColor Yellow
    $missing = @()
    foreach ($iso in $RequiredISOs) {
        $p = Join-Path $IsoPath $iso
        if (Test-Path $p) { Write-Host "  [OK] $iso" -ForegroundColor Green }
        else { Write-Host "  [MISSING] $iso" -ForegroundColor Red; $missing += $iso }
    }
    if ($missing.Count -gt 0) {
        Write-Host "  [ERROR] Missing ISOs in ${IsoPath}: $($missing -join ', ')" -ForegroundColor Red
        pause
        return
    }

    # Import module
    Write-Host "Importing AutomatedLab module..." -ForegroundColor Yellow
    if (-not (Import-AutomatedLabModule)) {
        pause
        return
    }

    try {
        # Remove existing lab if present
        if (Get-Lab -List | Where-Object { $_ -eq $LabName }) {
            Write-Host "  Lab '$LabName' already exists. Removing..." -ForegroundColor Yellow
            Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue

            $labMetaPath = Join-Path 'C:\ProgramData\AutomatedLab\Labs' $LabName
            if (Test-Path $labMetaPath) {
                Remove-Item -Path $labMetaPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host "  [OK] Existing lab removed" -ForegroundColor Green
        }

        # Increase timeouts for resource-constrained hosts
        Write-Host "Configuring AutomatedLab timeouts..." -ForegroundColor Yellow
        Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionRestartAfterDcpromo -Value 90
        Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionAdwsReady -Value 120
        Set-PSFConfig -Module AutomatedLab -Name Timeout_StartLabMachine_Online -Value 90
        Set-PSFConfig -Module AutomatedLab -Name Timeout_WaitLabMachine_Online -Value 90

        # Create lab definition
        Write-Host "Creating lab definition..." -ForegroundColor Yellow
        New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath $LabPath

        # Remove stale VMs
        Write-Host "Checking for stale VMs..." -ForegroundColor Yellow
        foreach ($vmName in $LabVMs) {
            if (-not (Remove-HyperVVMStale -VMName $vmName -Context 'initial cleanup')) {
                throw "Failed to remove stale VM '$vmName'. Remove it manually in Hyper-V Manager."
            }
        }

        # Ensure vSwitch + NAT exist
        Write-Host "Configuring network ($LabSwitch / $AddressSpace)..." -ForegroundColor Yellow

        if (-not (Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue)) {
            New-VMSwitch -Name $LabSwitch -SwitchType Internal | Out-Null
            Write-Host "  [OK] Created VMSwitch: $LabSwitch" -ForegroundColor Green
        }

        $ifAlias = "vEthernet ($LabSwitch)"
        $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -eq $GatewayIp }
        if (-not $hasGw) {
            Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
            Write-Host "  [OK] Set host gateway IP: $GatewayIp" -ForegroundColor Green
        }

        $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
        if (-not $nat) {
            New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
            Write-Host "  [OK] Created NAT: $NatName" -ForegroundColor Green
        }

        # Register network with AutomatedLab
        Add-LabVirtualNetworkDefinition -Name $LabSwitch -AddressSpace $AddressSpace -HyperVProperties @{ SwitchType = 'Internal' }

        # Set credentials and domain
        Set-LabInstallationCredential -Username $LabInstallUser -Password $AdminPassword
        Add-LabDomainDefinition -Name $DomainName -AdminUser $LabInstallUser -AdminPassword $AdminPassword

        # ============================================================
        # MACHINE DEFINITIONS (4-VM topology with DSC Pull Server)
        # ============================================================
        Write-Host "Defining machines (dc1 + svr1 + dsc + ws1)..." -ForegroundColor Cyan

        # dc1 - Domain Controller
        Add-LabMachineDefinition -Name 'dc1' `
            -Roles RootDC, CaRoot `
            -DomainName $DomainName `
            -Network $LabSwitch `
            -IpAddress $dc1_Ip -Gateway $GatewayIp -DnsServer1 $dc1_Ip `
            -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
            -Memory $DC_Memory -MinMemory $DC_MinMemory -MaxMemory $DC_MaxMemory `
            -Processors $Processors

        # svr1 - Member Server
        Add-LabMachineDefinition -Name 'svr1' `
            -DomainName $DomainName `
            -Network $LabSwitch `
            -IpAddress $svr1_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
            -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
            -Memory $Server_Memory -MinMemory $Server_MinMemory -MaxMemory $Server_MaxMemory `
            -Processors $Processors

        # dsc - DSC Pull Server
        Add-LabMachineDefinition -Name 'dsc' `
            -Roles DSCPullServer `
            -DomainName $DomainName `
            -Network $LabSwitch `
            -IpAddress $dsc_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
            -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
            -Memory $DSC_Memory -MinMemory $DSC_MinMemory -MaxMemory $DSC_MaxMemory `
            -Processors $Processors

        # ws1 - Windows 11 Client
        Add-LabMachineDefinition -Name 'ws1' `
            -DomainName $DomainName `
            -Network $LabSwitch `
            -IpAddress $ws1_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
            -OperatingSystem 'Windows 11 Enterprise Evaluation' `
            -Memory $Client_Memory -MinMemory $Client_MinMemory -MaxMemory $Client_MaxMemory `
            -Processors $Processors

        # ============================================================
        # INSTALL LAB
        # ============================================================
        Write-Host "Installing lab (this will take 15-30 minutes)..." -ForegroundColor Cyan
        Write-Host "  dc1  - Domain Controller" -ForegroundColor White
        Write-Host "  svr1 - Member Server" -ForegroundColor White
        Write-Host "  dsc  - DSC Pull Server" -ForegroundColor Green
        Write-Host "  ws1  - Windows 11 Client" -ForegroundColor White
        Write-Host ""

        Install-Lab -ErrorAction Stop

        Write-Host ""
        Write-Host "[SUCCESS] Lab installation complete!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Lab Summary:" -ForegroundColor Cyan
        Write-Host "  dc1  - Domain Controller ($dc1_Ip)" -ForegroundColor White
        Write-Host "  svr1 - Member Server ($svr1_Ip)" -ForegroundColor White
        Write-Host "  dsc  - DSC Pull Server ($dsc_Ip)" -ForegroundColor Green
        Write-Host "  ws1  - Windows 11 Client ($ws1_Ip)" -ForegroundColor White
        Write-Host ""
        Write-Host "Domain: $DomainName" -ForegroundColor Cyan
        Write-Host "Admin: $DomainName\$LabInstallUser (Password: $AdminPassword)" -ForegroundColor Yellow
        Write-Host ""

        # Create LabReady checkpoint
        Write-Host "Creating LabReady checkpoint..." -ForegroundColor Yellow
        $checkpoints = Get-LabSnapshot -ErrorAction SilentlyContinue
        foreach ($checkpoint in $checkpoints) {
            Remove-LabSnapshot -Snapshot $checkpoint -ErrorAction SilentlyContinue
        }
        $labVMs = Get-LabVM -ErrorAction SilentlyContinue
        foreach ($vm in $labVMs) {
            Checkpoint-LabVM -VMName $vm.Name -SnapshotName "LabReady" -ErrorAction SilentlyContinue
        }
        Write-Host "  [OK] LabReady checkpoint created" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] Lab installation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        pause
        $script:exitCode = $EXIT_ERROR
        return
    }
}

function Invoke-StartLab {
    Write-Host ""
    Write-Host "=== Starting Lab ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        $lab = Import-Lab -Name $LabName -ErrorAction Stop
        Start-Lab -ErrorAction Stop

        Write-Host ""
        Write-Host "[SUCCESS] Lab started!" -ForegroundColor Green
        Write-Host ""
        Write-Host "VMs:" -ForegroundColor Cyan
        Write-Host "  dc1  - Domain Controller ($dc1_Ip)" -ForegroundColor White
        Write-Host "  svr1 - Member Server ($svr1_Ip)" -ForegroundColor White
        Write-Host "  dsc  - DSC Pull Server ($dsc_Ip)" -ForegroundColor Green
        Write-Host "  ws1  - Windows 11 Client ($ws1_Ip)" -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Host "[ERROR] Failed to start lab: $($_.Exception.Message)" -ForegroundColor Red
        pause
        $script:exitCode = $EXIT_ERROR
    }

    pause
}

function Invoke-StopLab {
    Write-Host ""
    Write-Host "=== Stopping Lab ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        Stop-Lab -ErrorAction Stop
        Write-Host ""
        Write-Host "[SUCCESS] Lab stopped!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "[ERROR] Failed to stop lab: $($_.Exception.Message)" -ForegroundColor Red
        pause
        $script:exitCode = $EXIT_ERROR
    }

    pause
}

function Invoke-RestartLab {
    Write-Host ""
    Write-Host "=== Restarting Lab ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        Stop-Lab -ErrorAction Stop
        Start-Lab -ErrorAction Stop
        Write-Host ""
        Write-Host "[SUCCESS] Lab restarted!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "[ERROR] Failed to restart lab: $($_.Exception.Message)" -ForegroundColor Red
        pause
        $script:exitCode = $EXIT_ERROR
    }

    pause
}

function Invoke-SuspendLab {
    Write-Host ""
    Write-Host "=== Suspending Lab ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        Stop-Lab -ErrorAction Stop
        Write-Host ""
        Write-Host "[SUCCESS] Lab suspended (saved state)!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "[ERROR] Failed to suspend lab: $($_.Exception.Message)" -ForegroundColor Red
        pause
        $script:exitCode = $EXIT_ERROR
    }

    pause
}

function Invoke-ShowStatus {
    Write-Host ""
    Write-Host "=== Lab Status ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        $lab = Import-Lab -Name $LabName -ErrorAction Stop
        $vms = Get-LabVM -ErrorAction Stop

        Write-Host ""
        Write-Host "Lab: $LabName" -ForegroundColor Cyan
        Write-Host "Domain: $DomainName" -ForegroundColor Cyan
        Write-Host ""

        foreach ($vm in $vms) {
            $statusColor = switch ($vm.State) {
                "Running"   { "Green" }
                "Off"       { "Gray" }
                "Saved"     { "Yellow" }
                default     { "Yellow" }
            }

            Write-Host "  $($vm.Name.PadRight(15)) " -NoNewline -ForegroundColor Cyan
            Write-Host ($vm.State.PadRight(12)) -NoNewline -ForegroundColor $statusColor

            # Show roles
            $roles = ($vm.Roles | ForEach-Object { $_.Name }) -join ', '
            if ($roles) {
                Write-Host " [$roles]" -ForegroundColor DarkGray
            }
            Write-Host ""
        }
    }
    catch {
        Write-Host "[ERROR] Failed to get lab status: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    pause
}

function Invoke-CreateCheckpoint {
    Write-Host ""
    Write-Host "=== Creating LabReady Checkpoint ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        # Remove existing LabReady checkpoints
        Write-Host "Removing existing LabReady checkpoints..." -ForegroundColor Yellow
        $checkpoints = Get-LabSnapshot -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'LabReady' }
        foreach ($checkpoint in $checkpoints) {
            Remove-LabSnapshot -Snapshot $checkpoint -ErrorAction SilentlyContinue
        }

        # Create new LabReady checkpoints for all VMs
        Write-Host "Creating LabReady checkpoints..." -ForegroundColor Yellow
        $labVMs = Get-LabVM -ErrorAction Stop
        foreach ($vm in $labVMs) {
            Checkpoint-LabVM -VMName $vm.Name -SnapshotName "LabReady" -ErrorAction Stop
        }

        Write-Host ""
        Write-Host "[SUCCESS] LabReady checkpoint created!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "[ERROR] Failed to create checkpoint: $($_.Exception.Message)" -ForegroundColor Red
        pause
        $script:exitCode = $EXIT_ERROR
    }

    pause
}

function Invoke-RestoreCheckpointMenu {
    Write-Host ""
    Write-Host "=== Available Checkpoints ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        $checkpoints = Get-LabSnapshot -ErrorAction SilentlyContinue

        if ($null -eq $checkpoints -or $checkpoints.Count -eq 0) {
            Write-Host "No checkpoints found." -ForegroundColor Yellow
            pause
            return
        }

        $checkpointNames = $checkpoints | Select-Object -ExpandProperty Name -Unique
        for ($i = 0; $i -lt $checkpointNames.Count; $i++) {
            Write-Host "  $($i + 1). $($checkpointNames[$i])" -ForegroundColor Cyan
        }

        Write-Host ""
        $selection = Read-Host "Select checkpoint to restore (0 to cancel)"

        if ($selection -eq "0") {
            return
        }

        $index = [int]$selection - 1
        if ($index -ge 0 -and $index -lt $checkpointNames.Count) {
            $checkpointName = $checkpointNames[$index]
            Write-Host "Restoring checkpoint: $checkpointName" -ForegroundColor Yellow
            Restore-LabSnapshot -SnapshotName $checkpointName -ErrorAction Stop
            Write-Host ""
            Write-Host "[SUCCESS] Checkpoint restored!" -ForegroundColor Green
            Write-Host ""
        }
        else {
            Write-Host "Invalid selection." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[ERROR] Failed to restore checkpoint: $($_.Exception.Message)" -ForegroundColor Red
    }

    pause
}

function Invoke-SetupNAT {
    Write-Host ""
    Write-Host "=== Setup NAT Network ===" -ForegroundColor Cyan

    try {
        # Ensure vSwitch exists
        if (-not (Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue)) {
            New-VMSwitch -Name $LabSwitch -SwitchType Internal | Out-Null
            Write-Host "  [OK] Created VMSwitch: $LabSwitch" -ForegroundColor Green
        }
        else {
            Write-Host "  [OK] VMSwitch exists: $LabSwitch" -ForegroundColor Green
        }

        # Configure gateway IP
        $ifAlias = "vEthernet ($LabSwitch)"
        $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -eq $GatewayIp }
        if (-not $hasGw) {
            Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
            Write-Host "  [OK] Set host gateway IP: $GatewayIp" -ForegroundColor Green
        }
        else {
            Write-Host "  [OK] Host gateway IP already set: $GatewayIp" -ForegroundColor Green
        }

        # Create NAT
        $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
        if (-not $nat) {
            New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
            Write-Host "  [OK] Created NAT: $NatName" -ForegroundColor Green
        }
        else {
            Write-Host "  [OK] NAT exists: $NatName" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "[SUCCESS] NAT network configured!" -ForegroundColor Green
        Write-Host "Switch: $LabSwitch" -ForegroundColor Cyan
        Write-Host "Gateway: $GatewayIp" -ForegroundColor Cyan
        Write-Host "NAT: $NatName" -ForegroundColor Cyan
        Write-Host "Address Space: $AddressSpace" -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        Write-Host "[ERROR] Failed to setup NAT: $($_.Exception.Message)" -ForegroundColor Red
        pause
        $script:exitCode = $EXIT_ERROR
    }

    pause
}

function Invoke-DSCStatus {
    Write-Host ""
    Write-Host "=== DSC Pull Server Status ===" -ForegroundColor Cyan
    Import-AutomatedLabModule

    try {
        $lab = Import-Lab -Name $LabName -ErrorAction Stop
        $dscVM = Get-LabVM -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'dsc' }

        if ($null -eq $dscVM) {
            Write-Host "[INFO] DSC VM not found. Build the lab first." -ForegroundColor Yellow
            Write-Host ""
            pause
            return
        }

        Write-Host "DSC Pull Server: dsc ($dsc_Ip)" -ForegroundColor Green
        Write-Host "State: $($dscVM.State)" -ForegroundColor Cyan
        Write-Host ""

        # Check if DSC web service is running
        Write-Host "Checking DSC web service..." -ForegroundColor Yellow
        try {
            $dscIP = $dsc_Ip
            $dscUrl = "http://${dscIP}:8080/PSDSCPullServer.svc/"

            $response = Invoke-WebRequest -Uri $dscUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue

            if ($response.StatusCode -eq 200) {
                Write-Host "  [OK] DSC Pull Server is responding!" -ForegroundColor Green
                Write-Host "  URL: $dscUrl" -ForegroundColor Gray
            }
            else {
                Write-Host "  [WARN] DSC Pull Server returned status: $($response.StatusCode)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  [INFO] DSC Pull Server not responding yet (may still be initializing)" -ForegroundColor Yellow
        }

        Write-Host ""

        # Show DSC configuration
        Write-Host "DSC Pull Server Features:" -ForegroundColor Cyan
        Write-Host "  - Pull endpoint: http://${dscIP}:8080/PSDSCPullServer.svc/" -ForegroundColor White
        Write-Host "  - Registration endpoint: http://${dscIP}:8080/PSDSCRegisterServer.svc/" -ForegroundColor White
        Write-Host "  - Configuration endpoint: http://${dscIP}:8080/PSDSCConfigurationService.svc/" -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Host "[ERROR] Failed to check DSC status: $($_.Exception.Message)" -ForegroundColor Red
    }

    pause
}

function Invoke-ResetLab {
    Write-Host ""
    Write-Host "=== Reset Lab ===" -ForegroundColor Cyan
    Write-Host "This will remove all VMs, checkpoints, and the virtual switch." -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? (yes/NO)"

    if ($confirm -eq "yes") {
        Import-AutomatedLabModule

        try {
            # First, try to import and remove the lab properly
            $labExists = Get-Lab -List | Where-Object { $_ -eq $LabName }

            if ($labExists) {
                Write-Host "Importing lab definition..." -ForegroundColor Yellow
                Import-Lab -Name $LabName -ErrorAction SilentlyContinue

                Write-Host "Removing VMs..." -ForegroundColor Yellow

                # Show VMs that will be removed
                $vms = Get-LabVM -ErrorAction SilentlyContinue
                if ($vms) {
                    foreach ($vm in $vms) {
                        Write-Host "  - $($vm.Name) ($($vm.State))" -ForegroundColor Cyan
                    }
                }

                # Remove using AutomatedLab
                Remove-Lab -Name $LabName -Confirm:$false -ErrorAction Stop
                Write-Host "  [OK] Removed lab via AutomatedLab" -ForegroundColor Green
            }
            else {
                Write-Host "Lab definition not found - performing manual cleanup..." -ForegroundColor Yellow
            }

            # Manual cleanup: Remove any remaining VMs
            Write-Host "Checking for remaining VMs..." -ForegroundColor Yellow
            foreach ($vmName in $LabVMs) {
                if (Remove-HyperVVMStale -VMName $vmName -Context 'reset lab' -MaxAttempts 1) {
                    Write-Host "  [OK] Removed VM '$vmName'" -ForegroundColor Green
                }
            }

            # Remove lab metadata
            $labMetaPath = Join-Path 'C:\ProgramData\AutomatedLab\Labs' $LabName
            if (Test-Path $labMetaPath) {
                Remove-Item -Path $labMetaPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] Removed lab metadata" -ForegroundColor Green
            }

            # Also remove the switch
            $switch = Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue
            if ($switch) {
                Remove-VMSwitch -Name $LabSwitch -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] Removed virtual switch" -ForegroundColor Green
            }

            # Remove NAT
            $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
            if ($nat) {
                Remove-NetNat -Name $NatName -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "  [OK] Removed NAT" -ForegroundColor Green
            }

            Write-Host ""
            Write-Host "[SUCCESS] Lab reset complete!" -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Host "[ERROR] Failed to reset lab: $($_.Exception.Message)" -ForegroundColor Red

            # Fallback: Try manual cleanup
            Write-Host "Attempting manual cleanup..." -ForegroundColor Yellow
            foreach ($vmName in $LabVMs) {
                Remove-HyperVVMStale -VMName $vmName -Context 'fallback cleanup' -MaxAttempts 3 | Out-Null
            }
        }
    }
    else {
        Write-Host "Reset cancelled." -ForegroundColor Yellow
    }

    Write-Host ""
    pause
}

function Show-Help {
    Write-Host ""
    Write-Host "SimpleLab v4.0.1 - Windows Domain Lab + DSC Pull Server" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\SimpleLab.ps1 [Operation]"
    Write-Host ""
    Write-Host "Operations:" -ForegroundColor White
    Write-Host "  Build       - Complete lab build with DSC Pull Server"
    Write-Host "  Start       - Start all lab VMs"
    Write-Host "  Stop        - Stop all lab VMs"
    Write-Host "  Restart     - Restart all lab VMs"
    Write-Host "  Suspend     - Suspend all lab VMs (save state)"
    Write-Host "  Status      - Display detailed lab status"
    Write-Host "  Checkpoint  - Create LabReady checkpoint"
    Write-Host "  NAT         - Setup NAT network for Internet access"
    Write-Host "  DSCStatus  - Show DSC Pull Server status"
    Write-Host "  Reset       - Complete lab teardown"
    Write-Host "  Menu        - Show interactive menu (default)"
    Write-Host "  Help        - Show this help message"
    Write-Host ""
    Write-Host "Requirements:" -ForegroundColor White
    Write-Host "  - AutomatedLab module (Install-Module AutomatedLab)"
    Write-Host "  - Hyper-V role enabled"
    Write-Host "  - ISOs: server2019.iso, windows11.iso in C:\LabSources\ISOs"
    Write-Host ""
    Write-Host "VMs Created:" -ForegroundColor White
    Write-Host "  dc1  - Domain Controller (RootDC, CaRoot)"
    Write-Host "  svr1 - Member Server"
    Write-Host "  dsc  - DSC Pull Server"
    Write-Host "  ws1  - Windows 11 Client"
    Write-Host ""
    Write-Host "Exit Codes:" -ForegroundColor White
    Write-Host "  0 = Success"
    Write-Host "  1 = General error"
    Write-Host "  2 = Validation failure"
    Write-Host "  3 = Operation cancelled"
    Write-Host ""
}

function Invoke-Operation {
    param([string]$Op)

    switch ($Op) {
        "Build" {
            Write-Host "SimpleLab v4.0.1 - Building Lab with DSC..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-BuildLab
        }
        "Start" {
            Write-Host "SimpleLab v4.0.1 - Starting Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-StartLab
        }
        "Stop" {
            Write-Host "SimpleLab v4.0.1 - Stopping Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-StopLab
        }
        "Restart" {
            Write-Host "SimpleLab v4.0.1 - Restarting Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-RestartLab
        }
        "Suspend" {
            Write-Host "SimpleLab v4.0.1 - Suspending Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-SuspendLab
        }
        "Status" {
            Write-Host "SimpleLab v4.0.1 - Lab Status" -ForegroundColor Cyan
            Write-Host ""
            Invoke-ShowStatus
        }
        "Checkpoint" {
            Write-Host "SimpleLab v4.0.1 - Creating LabReady Checkpoint..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-CreateCheckpoint
        }
        "NAT" {
            Write-Host "SimpleLab v4.0.1 - Setting up NAT Network..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-SetupNAT
        }
        "DSCStatus" {
            Write-Host "SimpleLab v4.0.1 - DSC Pull Server Status..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-DSCStatus
        }
        "Reset" {
            Write-Host "SimpleLab v4.0.1 - Resetting Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-ResetLab
        }
        "Menu" {
            $continue = $true
            while ($continue) {
                Clear-Host
                $selection = Show-Menu
                $continue = Invoke-MenuOperation -Selection $selection
            }
        }
        "Help" {
            Show-Help
        }
        default {
            Write-Host "Unknown operation: $Op" -ForegroundColor Red
            Write-Host "Run '.\SimpleLab.ps1 -Help' for usage information." -ForegroundColor Yellow
            $script:exitCode = $EXIT_ERROR
        }
    }
}

# Main execution
try {
    Invoke-Operation -Op $Operation
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    $script:exitCode = $EXIT_ERROR
}

exit $script:exitCode
