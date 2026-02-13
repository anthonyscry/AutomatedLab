# New-AutomatedLab.ps1
# AutomatedLab deployment with DSC Pull Server
# VMs: dc1 (DC), svr1 (Member Server), ws1 (Client), dsc (DSC Pull Server)

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$ForceRebuild,

    [Parameter()]
    [switch]$NonInteractive
)

# ============================================================
# CONFIGURATION
# ============================================================

$LabName = 'AutomatedLab'
$DomainName = 'simplelab.local'

# VM Names
$VMs = @('dc1', 'svr1', 'ws1', 'dsc')

# Networking
$LabSwitch = 'AutomatedLab'
$AddressSpace = '10.0.10.0/24'
$GatewayIp = '10.0.10.1'
$NatName = "${LabSwitch}NAT"

# IP Addresses
$DC1_Ip   = '10.0.10.10'
$SVR1_Ip  = '10.0.10.20'
$WS1_Ip   = '10.0.10.30'
$DSC_Ip   = '10.0.10.40'
$DnsIp    = $DC1_Ip

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

# Processors
$Processors = 4

# Required ISOs
$RequiredISOs = @('server2019.iso', 'windows11.iso')

# ============================================================
# LOAD COMMON FUNCTIONS
# ============================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $CommonPath) { . $CommonPath }

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Invoke-WindowsSshKeygen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrivateKeyPath,
        [Parameter()][string]$Comment = ""
    )

    $sshExe = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"
    if (-not (Test-Path $sshExe)) {
        throw "OpenSSH ssh-keygen not found at $sshExe"
    }

    $priv = $PrivateKeyPath
    $pub  = "$PrivateKeyPath.pub"
    $dir = Split-Path -Parent $priv
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $cmd = '"' + $sshExe + '" -t ed25519 -f "' + $priv + '" -N ""'
    if ($Comment -and $Comment.Trim().Length -gt 0) {
        $cmd += ' -C "' + $Comment.Replace('"','\"') + '"'
    }

    & $env:ComSpec /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed (exit code $LASTEXITCODE)." }
    if (-not (Test-Path $priv) -or -not (Test-Path $pub)) {
        throw "ssh-keygen reported success but key files were not found"
    }
}

# ============================================================
# LOGGING
# ============================================================
$logDir  = "$LabSourcesRoot\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = "$logDir\Deploy-AutomatedLab_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
    # ============================================================
    # PRE-FLIGHT CHECKS
    # ============================================================
    Write-Host "`n[PRE-FLIGHT] Checking AutomatedLab module..." -ForegroundColor Cyan

    if (-not (Get-Module -ListAvailable -Name AutomatedLab -ErrorAction SilentlyContinue)) {
        throw "AutomatedLab module not installed. Run: Install-Module AutomatedLab -Force -Scope CurrentUser"
    }

    Import-Module AutomatedLab -ErrorAction Stop
    Write-Host "  [OK] AutomatedLab module imported" -ForegroundColor Green

    Write-Host "`n[PRE-FLIGHT] Checking ISOs..." -ForegroundColor Cyan
    $missing = @()
    foreach ($iso in $RequiredISOs) {
        $p = Join-Path $IsoPath $iso
        if (Test-Path $p) { Write-Host "  [OK] $iso" -ForegroundColor Green }
        else { Write-Host "  [MISSING] $iso" -ForegroundColor Red; $missing += $iso }
    }
    if ($missing.Count -gt 0) {
        throw "Missing ISOs in ${IsoPath}: $($missing -join ', ')"
    }

    # ============================================================
    # REMOVE EXISTING LAB IF PRESENT
    # ============================================================
    if (Get-Lab -List | Where-Object { $_ -eq $LabName }) {
        Write-Host "`n[CLEANUP] Lab '$LabName' already exists." -ForegroundColor Yellow
        $allowRebuild = $false
        if ($ForceRebuild -or $NonInteractive) {
            $allowRebuild = $true
        } else {
            $response = Read-Host "  Remove and rebuild? (y/n)"
            if ($response -eq 'y') { $allowRebuild = $true }
        }

        if ($allowRebuild) {
            Write-Host "  Removing existing lab..." -ForegroundColor Yellow
            Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue

            $labMetaPath = Join-Path 'C:\ProgramData\AutomatedLab\Labs' $LabName
            if (Test-Path $labMetaPath) {
                Remove-Item -Path $labMetaPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host "  Removal complete." -ForegroundColor Green
        } else {
            throw "Aborting by user choice."
        }
    }

    # ============================================================
    # LAB DEFINITION
    # ============================================================
    Write-Host "`n[LAB] Defining lab '$LabName'..." -ForegroundColor Cyan

    # Increase timeouts for resource-constrained hosts
    Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionRestartAfterDcpromo -Value 90
    Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionAdwsReady -Value 120
    Set-PSFConfig -Module AutomatedLab -Name Timeout_StartLabMachine_Online -Value 90
    Set-PSFConfig -Module AutomatedLab -Name Timeout_WaitLabMachine_Online -Value 90

    New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath $LabPath

    # Remove stale VMs from previous runs
    Write-Host "  Checking for stale VMs..." -ForegroundColor Yellow
    foreach ($vmName in $VMs) {
        if (-not (Remove-HyperVVMStale -VMName $vmName -Context 'initial cleanup')) {
            throw "Failed to remove stale VM '$vmName'"
        }
    }

    # Ensure vSwitch + NAT exist
    Write-Host "  Ensuring Hyper-V lab switch + NAT ($LabSwitch / $AddressSpace)..." -ForegroundColor Yellow

    if (-not (Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name $LabSwitch -SwitchType Internal | Out-Null
        Write-Host "    [OK] Created VMSwitch: $LabSwitch" -ForegroundColor Green
    } else {
        Write-Host "    [OK] VMSwitch exists: $LabSwitch" -ForegroundColor Green
    }

    $ifAlias = "vEthernet ($LabSwitch)"
    $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -eq $GatewayIp }
    if (-not $hasGw) {
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
        Write-Host "    [OK] Set host gateway IP: $GatewayIp" -ForegroundColor Green
    }

    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-Host "    [OK] Created NAT: $NatName" -ForegroundColor Green
    }

    # Register network with AutomatedLab
    Add-LabVirtualNetworkDefinition -Name $LabSwitch -AddressSpace $AddressSpace -HyperVProperties @{ SwitchType = 'Internal' }

    Set-LabInstallationCredential -Username $LabInstallUser -Password $AdminPassword
    Add-LabDomainDefinition -Name $DomainName -AdminUser $LabInstallUser -AdminPassword $AdminPassword

    # ============================================================
    # MACHINE DEFINITIONS (4-VM topology with DSC Pull Server)
    # ============================================================
    Write-Host "`n[LAB] Defining machines (dc1 + svr1 + ws1 + dsc)..." -ForegroundColor Cyan

    # dc1 - Domain Controller
    Add-LabMachineDefinition -Name 'dc1' `
        -Roles RootDC, CaRoot `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $DC1_Ip -Gateway $GatewayIp -DnsServer1 $DC1_Ip `
        -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
        -Memory $DC_Memory -MinMemory $DC_MinMemory -MaxMemory $DC_MaxMemory `
        -Processors $Processors

    # svr1 - Member Server
    Add-LabMachineDefinition -Name 'svr1' `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $SVR1_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
        -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
        -Memory $Server_Memory -MinMemory $Server_MinMemory -MaxMemory $Server_MaxMemory `
        -Processors $Processors

    # dsc - DSC Pull Server
    Add-LabMachineDefinition -Name 'dsc' `
        -Roles DSCPullServer `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $DSC_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
        -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
        -Memory $DSC_Memory -MinMemory $DSC_MinMemory -MaxMemory $DSC_MaxMemory `
        -Processors $Processors

    # ws1 - Windows 11 Client
    Add-LabMachineDefinition -Name 'ws1' `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $WS1_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
        -OperatingSystem 'Windows 11 Enterprise Evaluation' `
        -Memory $Client_Memory -MinMemory $Client_MinMemory -MaxMemory $Client_MaxMemory `
        -Processors $Processors

    # ============================================================
    # INSTALL LAB
    # ============================================================
    Write-Host "`n[INSTALL] Installing lab (dc1 + svr1 + dsc + ws1)..." -ForegroundColor Cyan

    # Final stale VM check
    Write-Host "  Final stale-VM check before Install-Lab..." -ForegroundColor Yellow
    foreach ($vmName in $VMs) {
        if (-not (Remove-HyperVVMStale -VMName $vmName -Context 'final pre-install guard')) {
            throw "VM '$vmName' still exists. Remove it manually."
        }
    }

    Install-Lab -ErrorAction Stop

    Write-Host "`n[SUCCESS] Lab installation complete!" -ForegroundColor Green
    Write-Host "`nVMs created:" -ForegroundColor Cyan
    Write-Host "  dc1  - Domain Controller (RootDC, CaRoot)" -ForegroundColor White
    Write-Host "  svr1 - Member Server" -ForegroundColor White
    Write-Host "  dsc  - DSC Pull Server" -ForegroundColor Green
    Write-Host "  ws1  - Windows 11 Client" -ForegroundColor White
    Write-Host "`nIP Addresses:" -ForegroundColor Cyan
    Write-Host "  dc1  - $DC1_Ip" -ForegroundColor White
    Write-Host "  svr1 - $SVR1_Ip" -ForegroundColor White
    Write-Host "  dsc  - $DSC_Ip" -ForegroundColor Green
    Write-Host "  ws1  - $WS1_Ip" -ForegroundColor White
    Write-Host "`nDomain: $DomainName" -ForegroundColor Cyan
    Write-Host "Admin: $DomainName\$LabInstallUser (Password: $AdminPassword)" -ForegroundColor Yellow
    Write-Host ""

}
catch {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
finally {
    Stop-Transcript
}

exit 0
