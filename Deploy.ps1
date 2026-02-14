# Deploy-SimpleLab.ps1 - Rebuildable 3-VM SimpleLab (AutomatedLab)
# Builds DC1 (AD/DNS/DHCP/CA), Server1 (Server 2019), Win11 (Windows 11) on Hyper-V
# Requires: AutomatedLab module, Hyper-V, ISOs in C:\LabSources\ISOs

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet('quick', 'full')]
    [string]$Mode = 'full',
    [switch]$NonInteractive,
    [switch]$ForceRebuild,
    [switch]$IncludeLIN1,
    [string]$AdminPassword
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ============================================================
# CONFIGURATION -- EDIT IF YOU WANT DIFFERENT IPs / NAMES
# ============================================================
# Config loaded from Lab-Config.ps1

# Deterministic lab install user (Windows is case-insensitive; Linux is not)
$LabInstallUser = if ([string]::IsNullOrWhiteSpace($LinuxUser)) { 'anthonyscry' } else { $LinuxUser }
# Password resolution: -AdminPassword param → Lab-Config.ps1 → env var → error
# Lab-Config.ps1 (dot-sourced above) sets $AdminPassword if our param was empty.
$AdminPassword = Resolve-LabPassword -Password $AdminPassword

$IsoPath        = "$LabSourcesRoot\ISOs"
$HostPublicKeyFileName = [System.IO.Path]::GetFileName($SSHPublicKey)

# Backward-compatible defaults for Server1 topology if Lab-Config.ps1 is older.
if (-not (Get-Variable -Name Server1_Ip -ErrorAction SilentlyContinue)) { $Server1_Ip = '10.0.10.20' }
if (-not (Get-Variable -Name Server_Memory -ErrorAction SilentlyContinue)) { $Server_Memory = $DC_Memory }
if (-not (Get-Variable -Name Server_MinMemory -ErrorAction SilentlyContinue)) { $Server_MinMemory = $DC_MinMemory }
if (-not (Get-Variable -Name Server_MaxMemory -ErrorAction SilentlyContinue)) { $Server_MaxMemory = $DC_MaxMemory }
if (-not (Get-Variable -Name Server_Processors -ErrorAction SilentlyContinue)) { $Server_Processors = $DC_Processors }

# Legacy aliases (for backward compatibility)
if (-not (Get-Variable -Name WSUS_Memory -ErrorAction SilentlyContinue)) { $WSUS_Memory = $Server_Memory }
if (-not (Get-Variable -Name WSUS_MinMemory -ErrorAction SilentlyContinue)) { $WSUS_MinMemory = $Server_MinMemory }
if (-not (Get-Variable -Name WSUS_MaxMemory -ErrorAction SilentlyContinue)) { $WSUS_MaxMemory = $Server_MaxMemory }
if (-not (Get-Variable -Name WSUS_Processors -ErrorAction SilentlyContinue)) { $WSUS_Processors = $Server_Processors }

# Remove-HyperVVMStale is provided by Lab-Common.ps1 (dot-sourced at line 19)

function Invoke-WindowsSshKeygen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PrivateKeyPath,
        [Parameter()][string]$Comment = ""
    )

    $sshExe = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"
    if (-not (Test-Path $sshExe)) {
        throw "OpenSSH ssh-keygen not found at $sshExe. Install Windows optional feature: OpenSSH Client."
    }

    $priv = $PrivateKeyPath
    $pub  = "$PrivateKeyPath.pub"
    $dir = Split-Path -Parent $priv
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    # cmd.exe avoids PowerShell native-arg quoting weirdness
    $cmd = '"' + $sshExe + '" -t ed25519 -f "' + $priv + '" -N ""'
    if ($Comment -and $Comment.Trim().Length -gt 0) {
        $cmd += ' -C "' + $Comment.Replace('"','\"') + '"'
    }

    & $env:ComSpec /c $cmd | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed (exit code $LASTEXITCODE)." }
    if (-not (Test-Path $priv) -or -not (Test-Path $pub)) {
        throw "ssh-keygen reported success but key files were not found: $priv / $pub"
    }
}

# ============================================================
# LOGGING
# ============================================================
$logDir  = "$LabSourcesRoot\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = "$logDir\Deploy-SimpleLab_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
    $deployStartTime = Get-Date
    Write-Host "`n[PRE-FLIGHT] Checking ISOs..." -ForegroundColor Cyan
    $missing = @()
    foreach ($iso in $RequiredISOs) {
        $p = Join-Path $IsoPath $iso
        if (Test-Path $p) { Write-LabStatus -Status OK -Message "$iso" }
        else { Write-Host "  [MISSING] $iso" -ForegroundColor Red; $missing += $iso }
    }
    if ($missing.Count -gt 0) {
        throw "Missing ISOs in ${IsoPath}: $($missing -join ', ')`nDownload from: https://www.microsoft.com/en-us/evalcenter/`nPlace files in: $IsoPath"
    }

    # Remove existing lab if present
    if (Get-Lab -List | Where-Object { $_ -eq $LabName }) {
        Write-Host "  Lab '$LabName' already exists." -ForegroundColor Yellow
        $allowRebuild = $false
        if ($ForceRebuild -or $NonInteractive) {
            $allowRebuild = $true
        } else {
            $response = Read-Host "  Remove lab '$LabName' and rebuild? Type 'yes' to confirm"
            if ($response -eq 'yes') { $allowRebuild = $true }
        }

        if ($allowRebuild) {
            Write-Host "  Removing existing lab..." -ForegroundColor Yellow
            $labMetaPath = Join-Path 'C:\ProgramData\AutomatedLab\Labs' $LabName
            Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            if (Get-Lab -List | Where-Object { $_ -eq $LabName }) {
                Write-LabStatus -Status WARN -Message "AutomatedLab still reports '$LabName' after removal attempt."
                if (Test-Path $labMetaPath) {
                    Remove-Item -Path $labMetaPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-LabStatus -Status WARN -Message "Removed stale lab metadata folder: $labMetaPath"
                }
            }

            Write-Host "  Removal step completed (continuing rebuild)." -ForegroundColor Green
        } else {
            throw "Aborting by user choice."
        }
    }

    # Ensure SSH keypair exists
    if (-not (Test-Path $SSHPrivateKey) -or -not (Test-Path $SSHPublicKey)) {
        Write-Host "  Generating host SSH keypair..." -ForegroundColor Yellow
        Invoke-WindowsSshKeygen -PrivateKeyPath $SSHPrivateKey -Comment "lab-opencode"
        Write-Host "  SSH keypair ready at $SSHKeyDir" -ForegroundColor Green
    } else {
        Write-Host "  SSH keypair found: $SSHPrivateKey" -ForegroundColor Green
    }

    # ============================================================
    # LAB DEFINITION
    # ============================================================
    Write-Host "`n[LAB] Defining lab '$LabName' (creating VM specifications)..." -ForegroundColor Cyan

    # Increase AutomatedLab timeouts for resource-constrained hosts
    # Values MUST be TimeSpan objects -- passing plain integers is interpreted as
    # ticks (nanoseconds), which effectively sets the timeout to zero.
    Write-Host "  Applying AutomatedLab timeout overrides..." -ForegroundColor Yellow
    Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionRestartAfterDcpromo -Value $AL_Timeout_DcRestart
    Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionAdwsReady -Value $AL_Timeout_AdwsReady
    Set-PSFConfig -Module AutomatedLab -Name Timeout_StartLabMachine_Online -Value $AL_Timeout_StartVM
    Set-PSFConfig -Module AutomatedLab -Name Timeout_WaitLabMachine_Online -Value $AL_Timeout_WaitVM
    Write-Host "    DC restart: ${AL_Timeout_DcRestart}m, ADWS ready: ${AL_Timeout_AdwsReady}m, VM start/wait: ${AL_Timeout_StartVM}m" -ForegroundColor Gray

    New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath $LabPath


    # Remove stale/conflicting VMs from previous failed runs.
    # This avoids "machine already exists" and broken-notes XML errors during Install-Lab.
    Write-Host "  Checking for stale lab VMs from prior runs..." -ForegroundColor Yellow
    foreach ($vmName in $LabVMs) {
        if (-not (Remove-HyperVVMStale -VMName $vmName -Context 'initial cleanup')) {
            throw "Failed to remove stale VM '$vmName'. Remove it manually in Hyper-V Manager, then re-run deploy."
        }
    }

    # Ensure vSwitch + NAT exist (idempotent)
    Write-Host "  Ensuring Hyper-V lab switch + NAT ($LabSwitch / $AddressSpace)..." -ForegroundColor Yellow

    if (-not (Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name $LabSwitch -SwitchType Internal | Out-Null
        Write-LabStatus -Status OK -Message "Created VMSwitch: $LabSwitch (Internal)" -Indent 2
    } else {
        Write-LabStatus -Status OK -Message "VMSwitch exists: $LabSwitch" -Indent 2
    }

    $ifAlias = "vEthernet ($LabSwitch)"
    $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -eq $GatewayIp }
    if (-not $hasGw) {
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
        Write-LabStatus -Status OK -Message "Set host gateway IP: $GatewayIp on $ifAlias" -Indent 2
    } else {
        Write-LabStatus -Status OK -Message "Host gateway IP already set: $GatewayIp" -Indent 2
    }

    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-LabStatus -Status OK -Message "Created NAT: $NatName for $AddressSpace" -Indent 2
    } elseif ($nat.InternalIPInterfaceAddressPrefix -ne $AddressSpace) {
        Write-LabStatus -Status WARN -Message "NAT '$NatName' exists with prefix '$($nat.InternalIPInterfaceAddressPrefix)'. Recreating..." -Indent 2
        Remove-NetNat -Name $NatName -Confirm:$false | Out-Null
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-LabStatus -Status OK -Message "Recreated NAT: $NatName for $AddressSpace" -Indent 2
    } else {
        Write-LabStatus -Status OK -Message "NAT exists: $NatName" -Indent 2
    }

    # Register network with AutomatedLab
    Add-LabVirtualNetworkDefinition -Name $LabSwitch -AddressSpace $AddressSpace -HyperVProperties @{ SwitchType = 'Internal' }

    # Use the deterministic install credential everywhere
    Set-LabInstallationCredential -Username $LabInstallUser -Password $AdminPassword
    Add-LabDomainDefinition -Name $DomainName -AdminUser $LabInstallUser -AdminPassword $AdminPassword

    # ============================================================
    # MACHINE DEFINITIONS (Simple 3-VM topology)
    # ============================================================
    if ($IncludeLIN1) {
        Write-Host "`n[LAB] Defining all machines (DC1 + Server1 + Win11 + LIN1)..." -ForegroundColor Cyan
    } else {
        Write-Host "`n[LAB] Defining Windows machines (DC1 + Server1 + Win11)..." -ForegroundColor Cyan
        Write-LabStatus -Status INFO -Message "Linux VM nodes are disabled for this run. Use -IncludeLIN1 to include Ubuntu."
    }

    Add-LabMachineDefinition -Name 'DC1' `
        -Roles RootDC, CaRoot `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $DC1_Ip -Gateway $GatewayIp -DnsServer1 $DC1_Ip `
        -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
        -Memory $DC_Memory -MinMemory $DC_MinMemory -MaxMemory $DC_MaxMemory `
        -Processors $DC_Processors

    Add-LabMachineDefinition -Name 'Server1' `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $Server1_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
        -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
        -Memory $Server_Memory -MinMemory $Server_MinMemory -MaxMemory $Server_MaxMemory `
        -Processors $Server_Processors

    Add-LabMachineDefinition -Name 'Win11' `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $Win11_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
        -OperatingSystem 'Windows 11 Enterprise Evaluation' `
        -Memory $CL_Memory -MinMemory $CL_MinMemory -MaxMemory $CL_MaxMemory `
        -Processors $CL_Processors

    # NOTE: LIN1 is NOT added to AutomatedLab machine definitions
    # It will be created manually after Install-Lab to work around
    # AutomatedLab's lack of Ubuntu 24.04 support

    # ============================================================
    # INSTALL LAB (DC1 + Server1 + Win11 via AutomatedLab)
    # LIN1 will be created manually after this step if -IncludeLIN1 is set
    # ============================================================
    Write-Host "`n[INSTALL] Installing Windows machines (DC1 + Server1 + Win11)..." -ForegroundColor Cyan
    $installStart = Get-Date
    Write-Host "  Started at: $(Get-Date -Format 'HH:mm:ss'). This typically takes 15-45 minutes." -ForegroundColor Gray


    # Final guard: stale VMs can occasionally survive prior cleanup and cause
    # AutomatedLab errors like "machine already exists" or malformed LIN1 notes XML.
    Write-Host "  Final stale-VM check before Install-Lab..." -ForegroundColor Yellow
    foreach ($vmName in $LabVMs) {
        if (-not (Remove-HyperVVMStale -VMName $vmName -Context 'final pre-install guard')) {
            throw "VM '$vmName' still exists before Install-Lab. Remove it manually in Hyper-V Manager and re-run."
        }
    }

    $installLabError = $null
    try {
        Install-Lab -ErrorAction Stop
    } catch {
        $installLabError = $_
        Write-LabStatus -Status WARN -Message "Install-Lab encountered an error: $($_.Exception.Message)"
        Write-LabStatus -Status WARN -Message "Exception type: $($_.Exception.GetType().FullName)"
        Write-Host "  Will attempt to validate and recover DC1 AD DS installation..." -ForegroundColor Yellow
    }
    $installElapsed = (Get-Date) - $installStart
    Write-Host ("  Install-Lab completed in {0:D2}m {1:D2}s" -f [int]$installElapsed.TotalMinutes, $installElapsed.Seconds) -ForegroundColor Green

    # ============================================================
    # STAGE 1 AD DS VALIDATION: Verify DC promotion succeeded
    # ============================================================
    Write-Host "`n[VALIDATE] Verifying Active Directory Domain Services (AD DS) promotion on DC1..." -ForegroundColor Cyan

    # Ensure DC1 VM is running
    $dc1Vm = Hyper-V\Get-VM -Name 'DC1' -ErrorAction SilentlyContinue
    if (-not $dc1Vm) {
        $installContext = ''
        if ($installLabError) {
            $installContext = " Install-Lab error: $($installLabError.Exception.Message)"
        }
        throw "DC1 VM was not created by Install-Lab.$installContext"
    }

    if ($dc1Vm -and $dc1Vm.State -ne 'Running') {
        Write-Host "  DC1 VM is $($dc1Vm.State). Starting..." -ForegroundColor Yellow
        Start-VM -Name 'DC1'
        $pollDeadline = [datetime]::Now.AddSeconds(60)
        while ([datetime]::Now -lt $pollDeadline) {
            $dc1State = (Hyper-V\Get-VM -Name 'DC1' -ErrorAction SilentlyContinue).State
            if ($dc1State -eq 'Running') { break }
            Start-Sleep -Seconds 5
        }
    }

    # Wait for WinRM to become reachable
    Write-Host "  Waiting for WinRM (Windows Remote Management, port 5985) on DC1..." -ForegroundColor Gray
    $winrmReady = $false
    for ($w = 1; $w -le 12; $w++) {
        $wrmCheck = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($wrmCheck.TcpTestSucceeded) { $winrmReady = $true; break }
        Write-Host "    WinRM attempt $w/12..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
    if (-not $winrmReady) {
        throw "DC1 WinRM (port 5985) is unreachable. Cannot validate AD DS installation.`nTroubleshooting:`n  1. Check DC1 VM is running in Hyper-V Manager`n  2. Verify DC1 IP ($DC1_Ip) is pingable: Test-Connection $DC1_Ip`n  3. Check Windows Firewall on DC1 allows WinRM (port 5985)"
    }

    # Check AD DS status on DC1
    $adStatus = Invoke-LabCommand -ComputerName 'DC1' -PassThru -ActivityName 'Validate-ADDS-Status' -ScriptBlock {
        $r = @{}
        $feat = Get-WindowsFeature AD-Domain-Services -ErrorAction SilentlyContinue
        $r.FeatureInstalled = ($feat -and $feat.InstallState -eq 'Installed')
        $ntds = Get-Service NTDS -ErrorAction SilentlyContinue
        $r.NTDSRunning = ($ntds -and $ntds.Status -eq 'Running')
        $cs = Get-CimInstance Win32_ComputerSystem
        $r.PartOfDomain = [bool]$cs.PartOfDomain
        $r.CurrentDomain = $cs.Domain
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            $forest = Get-ADForest -ErrorAction Stop
            $r.ForestName = $forest.Name
            $r.ADWorking = $true
        } catch {
            $r.ADWorking = $false
            $r.ForestName = ''
        }
        $r
    }

    if ($adStatus.NTDSRunning -and $adStatus.ADWorking -and $adStatus.CurrentDomain -eq $DomainName) {
        Write-LabStatus -Status OK -Message "DC1 is a domain controller for '$($adStatus.ForestName)'"
    } else {
        Write-LabStatus -Status WARN -Message "AD DS is NOT operational on DC1 after Install-Lab."
        Write-Host "    AD DS feature installed: $($adStatus.FeatureInstalled)" -ForegroundColor Yellow
        Write-Host "    NTDS service running:    $($adStatus.NTDSRunning)" -ForegroundColor Yellow
        Write-Host "    AD cmdlets working:      $($adStatus.ADWorking)" -ForegroundColor Yellow
        Write-Host "    Current domain:          '$($adStatus.CurrentDomain)' (expected: '$DomainName')" -ForegroundColor Yellow

        Write-Host "`n  [RECOVERY] Attempting manual AD DS promotion on DC1..." -ForegroundColor Yellow

        # Step 1: Ensure AD DS feature is installed
        if (-not $adStatus.FeatureInstalled) {
            Write-Host "    Installing AD-Domain-Services feature..." -ForegroundColor Yellow
            Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Recovery-ADDS-Feature' -ScriptBlock {
                Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
            } | Out-Null
            Write-LabStatus -Status OK -Message "AD DS feature installed" -Indent 2
        }

        # Step 2: Run Install-ADDSForest
        $netbiosDomain = ($DomainName -split '\.')[0].ToUpper()
        Write-Host "    Promoting DC1 to domain controller for '$DomainName' (NetBIOS: $netbiosDomain)..." -ForegroundColor Yellow

        Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Recovery-ADDSForest' -ScriptBlock {
            param($Domain, $Netbios, $SafeModePassword)
            $securePwd = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
            Install-ADDSForest `
                -DomainName $Domain `
                -DomainNetbiosName $Netbios `
                -SafeModeAdministratorPassword $securePwd `
                -InstallDns:$true `
                -NoRebootOnCompletion:$false `
                -Force `
                -WarningAction SilentlyContinue
        } -ArgumentList $DomainName, $netbiosDomain, $AdminPassword | Out-Null

        Write-LabStatus -Status OK -Message "Install-ADDSForest initiated. Waiting for DC1 to restart..." -Indent 2

        # Step 3: Wait for DC1 to go offline and come back
        # Wait for DC1 to go offline (restart initiated)
        $offlineDeadline = [datetime]::Now.AddSeconds(90)
        while ([datetime]::Now -lt $offlineDeadline) {
            $dc1Check = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if (-not $dc1Check.TcpTestSucceeded) { break }
            Start-Sleep -Seconds 5
        }

        $dc1Back = $false
        $restartDeadline = [datetime]::Now.AddMinutes(15)
        while ([datetime]::Now -lt $restartDeadline) {
            $rCheck = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($rCheck.TcpTestSucceeded) { $dc1Back = $true; break }
            Write-Host "    Waiting for DC1 to come back online..." -ForegroundColor Gray
            Start-Sleep -Seconds 15
        }
        if (-not $dc1Back) {
            throw "DC1 did not come back online after AD DS recovery promotion.`nTroubleshooting:`n  1. Connect to DC1 console via Hyper-V Manager`n  2. Check Event Viewer > Directory Services for errors`n  3. Try: Restart-VM -Name DC1 -Force"
        }

        # Step 4: Wait for ADWS and NTDS to start
        Write-Host "    Waiting for AD services to initialize..." -ForegroundColor Yellow
        # Wait for WinRM to become reachable before checking services
        $warmupDeadline = [datetime]::Now.AddSeconds(90)
        while ([datetime]::Now -lt $warmupDeadline) {
            $warmupCheck = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($warmupCheck.TcpTestSucceeded) { break }
            Write-Host "    Waiting for WinRM after AD promotion..." -ForegroundColor Gray
            Start-Sleep -Seconds 10
        }

        $adwsReady = $false
        $adwsDeadline = [datetime]::Now.AddMinutes(10)
        while ([datetime]::Now -lt $adwsDeadline) {
            try {
                $svcCheck = Invoke-LabCommand -ComputerName 'DC1' -PassThru -ScriptBlock {
                    @{
                        ADWS = (Get-Service ADWS -ErrorAction SilentlyContinue).Status.ToString()
                        NTDS = (Get-Service NTDS -ErrorAction SilentlyContinue).Status.ToString()
                    }
                }
                if ($svcCheck.ADWS -eq 'Running' -and $svcCheck.NTDS -eq 'Running') {
                    $adwsReady = $true; break
                }
                Write-Host "      ADWS: $($svcCheck.ADWS), NTDS: $($svcCheck.NTDS) - waiting..." -ForegroundColor Gray
            } catch {
                Write-Host "      Waiting for WinRM..." -ForegroundColor Gray
            }
            Start-Sleep -Seconds 20
        }
        if (-not $adwsReady) {
            throw "AD Web Services did not start on DC1 after recovery.`nTroubleshooting:`n  1. Connect to DC1 console via Hyper-V Manager`n  2. Run: Get-Service ADWS,NTDS | Format-Table Status,Name`n  3. Check Event Viewer > Directory Services`n  4. Try: Restart-Service ADWS -Force"
        }

        # Step 5: Final validation
        $finalAd = Invoke-LabCommand -ComputerName 'DC1' -PassThru -ScriptBlock {
            try {
                $forest = Get-ADForest -ErrorAction Stop
                @{ ADWorking = $true; ForestName = $forest.Name; Domain = (Get-CimInstance Win32_ComputerSystem).Domain }
            } catch {
                @{ ADWorking = $false; ForestName = ''; Domain = (Get-CimInstance Win32_ComputerSystem).Domain }
            }
        }
        if ($finalAd.ADWorking -and $finalAd.Domain -eq $DomainName) {
            Write-LabStatus -Status OK -Message "Recovery successful! DC1 is domain controller for '$($finalAd.ForestName)'"
        } else {
            throw "AD DS recovery failed. DC1 domain: '$($finalAd.Domain)', AD working: $($finalAd.ADWorking). Check DC1 event logs."
        }
    }

    # ============================================================
    # STAGE 1 VALIDATION: Network connectivity check
    # ============================================================
    Write-Host "`n[VALIDATE] Verifying host-to-DC1 network connectivity..." -ForegroundColor Cyan

    # 1. Ensure host adapter still has the gateway IP (Install-Lab may have interfered)
    $ifAlias = "vEthernet ($LabSwitch)"
    $hostIp = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -eq $GatewayIp }
    if (-not $hostIp) {
        Write-LabStatus -Status WARN -Message "Host gateway IP $GatewayIp missing on $ifAlias after Install-Lab. Re-applying..."
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
        Write-LabStatus -Status OK -Message "Re-applied host gateway IP: $GatewayIp"
    } else {
        Write-LabStatus -Status OK -Message "Host gateway IP intact: $GatewayIp"
    }

    # 2. Verify NAT still exists
    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        Write-LabStatus -Status WARN -Message "NAT '$NatName' missing after Install-Lab. Recreating..."
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-LabStatus -Status OK -Message "Recreated NAT: $NatName"
    } else {
        Write-LabStatus -Status OK -Message "NAT intact: $NatName"
    }

    # 3. Ping DC1 to verify L3 connectivity
    $pingOk = Test-Connection -ComputerName $DC1_Ip -Count 3 -Quiet -ErrorAction SilentlyContinue
    if (-not $pingOk) {
        throw "Cannot ping DC1 ($DC1_Ip) from host after Stage 1. Check vSwitch '$LabSwitch' and host adapter '$ifAlias'. Aborting before Stage 2."
    }
    Write-LabStatus -Status OK -Message "DC1 ($DC1_Ip) responds to ping"

    # 4. Verify WinRM connectivity (this is what AutomatedLab uses internally)
    $winrmOk = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if (-not $winrmOk.TcpTestSucceeded) {
        Write-LabStatus -Status WARN -Message "WinRM port 5985 not reachable on DC1 ($DC1_Ip). AD may still be starting."
        Write-Host "  Waiting 60s for WinRM to become available..." -ForegroundColor Yellow
        $retries = 6
        $winrmUp = $false
        for ($i = 1; $i -le $retries; $i++) {
            Start-Sleep -Seconds 10
            $check = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($check.TcpTestSucceeded) { $winrmUp = $true; break }
            Write-Host "    Retry $i/$retries..." -ForegroundColor Gray
        }
        if (-not $winrmUp) {
            throw "WinRM (port 5985) on DC1 ($DC1_Ip) is unreachable after 60s. Cannot proceed to Stage 2."
        }
    }
    Write-LabStatus -Status OK -Message "WinRM reachable on DC1 ($DC1_Ip):5985"
    Write-LabStatus -Status OK -Message "Stage 1 validation passed - proceeding to DHCP + Stage 2"

    # ============================================================
    # DC1: DHCP ROLE + SCOPE
    # ============================================================
    $dhcpSectionStart = Get-Date
    Write-Host "`n[DC1] Enabling DHCP (Dynamic Host Configuration Protocol) for Linux installs..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Install-DHCP-Role' -ScriptBlock {
        param($ScopeId, $StartRange, $EndRange, $Mask, $Router, $Dns, $DnsDomain)

        # Install DHCP role
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null

        # Authorize DHCP in AD (ignore if already authorized)
        try {
            if ($Dns) { Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -IPAddress $Dns | Out-Null }
        } catch {
            Write-Verbose "DHCP authorization already present or unavailable: $($_.Exception.Message)"
        }

        # Create scope if missing
        $existing = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId.IPAddressToString -eq $ScopeId }
        if (-not $existing) {
            Add-DhcpServerv4Scope -Name "SimpleLab" -StartRange $StartRange -EndRange $EndRange -SubnetMask $Mask -State Active | Out-Null
        }

        # Options
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -DnsServer @($Dns,'1.1.1.1') -DnsDomain $DnsDomain | Out-Null

        Restart-Service DHCPServer -ErrorAction SilentlyContinue
        Set-Service DHCPServer -StartupType Automatic

        "DHCP scope ready"
    } -ArgumentList $DhcpScopeId, $DhcpStart, $DhcpEnd, $DhcpMask, $GatewayIp, $DnsIp, $DomainName | Out-Null

    Write-LabStatus -Status OK -Message "DHCP scope configured: $DhcpScopeId ($DhcpStart - $DhcpEnd)"

    # Configure DNS forwarders on DC1 so lab clients can resolve external hosts (GitHub, package feeds).
    try {
        $dnsForwarderResults = @(Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Configure-DNS-Forwarders' -ScriptBlock {
            $targetForwarders = @('1.1.1.1','8.8.8.8')
            $existing = @(Get-DnsServerForwarder -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress.IPAddressToString })
            $missing = @($targetForwarders | Where-Object { $_ -notin $existing })

            if ($missing.Count -gt 0) {
                Add-DnsServerForwarder -IPAddress $missing -PassThru -ErrorAction Stop | Out-Null
            }

            $probe = Resolve-DnsName -Name 'release-assets.githubusercontent.com' -Type A -ErrorAction SilentlyContinue
            if ($probe) {
                return [pscustomobject]@{ Ready = $true; Message = 'DNS forwarders configured and external resolution verified.' }
            }

            return [pscustomobject]@{ Ready = $false; Message = 'Forwarders configured but external DNS probe did not resolve yet.' }
        } -PassThru)

        $dnsForwarderResult = @($dnsForwarderResults | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Ready' } | Select-Object -Last 1)
        if ($dnsForwarderResult.Count -gt 0 -and $dnsForwarderResult[0].Ready) {
            Write-LabStatus -Status OK -Message "$($dnsForwarderResult[0].Message)"
        } elseif ($dnsForwarderResult.Count -gt 0) {
            Write-LabStatus -Status WARN -Message "$($dnsForwarderResult[0].Message)"
        } else {
            Write-LabStatus -Status WARN -Message "DNS forwarder step returned no structured result."
        }
    } catch {
        Write-LabStatus -Status WARN -Message "DNS forwarder configuration failed: $($_.Exception.Message)"
    }
    $sectionElapsed = (Get-Date) - $dhcpSectionStart
    Write-Host "  Section completed in $([int]$sectionElapsed.TotalMinutes)m $($sectionElapsed.Seconds)s" -ForegroundColor DarkGray

    $lin1Ready = $false

    # ============================================================
    # LIN1: Manual VM creation (bypasses AutomatedLab -- no Ubuntu 24.04 support)
    # ============================================================
    if ($IncludeLIN1) {
        Write-Host "`n[LIN1] Creating LIN1 VM manually (AutomatedLab lacks Ubuntu 24.04 autoinstall support)..." -ForegroundColor Cyan

        $ubuntuIso = Join-Path $IsoPath 'ubuntu-24.04.3.iso'
        if (-not (Test-Path $ubuntuIso)) {
            Write-LabStatus -Status WARN -Message "Ubuntu ISO not found: $ubuntuIso. Skipping LIN1."
        } else {
            $lin1CreateSucceeded = $false
            try {
                # Remove stale LIN1 VM from previous runs
                Remove-HyperVVMStale -VMName 'LIN1' -Context 'LIN1 pre-create cleanup' | Out-Null

                # Generate password hash for autoinstall identity
                Write-Host "  Generating password hash..." -ForegroundColor Gray
                $lin1PwHash = Get-Sha512PasswordHash -Password $AdminPassword

                # Read SSH public key if available
                $lin1SshPubKey = ''
                if (Test-Path $SSHPublicKey) {
                    $lin1SshPubKey = (Get-Content $SSHPublicKey -Raw).Trim()
                }

                # Create CIDATA VHDX seed disk with autoinstall user-data
                $cidataPath = Join-Path $LabPath 'LIN1-cidata.vhdx'
                Write-Host "  Creating CIDATA seed disk with autoinstall config..." -ForegroundColor Gray
                New-CidataVhdx -OutputPath $cidataPath `
                    -Hostname 'LIN1' `
                    -Username $LabInstallUser `
                    -PasswordHash $lin1PwHash `
                    -SSHPublicKey $lin1SshPubKey

                # Create the LIN1 VM (Gen2, SecureBoot off, Ubuntu ISO + CIDATA VHDX)
                Write-Host "  Creating Hyper-V Gen2 VM..." -ForegroundColor Gray
                $lin1Vm = New-LinuxVM -UbuntuIsoPath $ubuntuIso -CidataVhdxPath $cidataPath -VMName 'LIN1'

                # Start VM -- Ubuntu autoinstall should proceed unattended
                Start-VM -Name 'LIN1'
                Write-LabStatus -Status OK -Message "LIN1 VM started. Ubuntu autoinstall in progress..."
                $lin1CreateSucceeded = $true
            }
            catch {
                Write-LabStatus -Status WARN -Message "LIN1 VM creation failed: $($_.Exception.Message)"
            }
            finally {
                if (-not $lin1CreateSucceeded) {
                    Write-Host "  Cleaning up partial LIN1 artifacts..." -ForegroundColor Gray
                    Remove-VM -Name 'LIN1' -Force -ErrorAction SilentlyContinue
                    Remove-Item (Join-Path $LabPath 'LIN1.vhdx') -Force -ErrorAction SilentlyContinue
                    Remove-Item (Join-Path $LabPath 'LIN1-cidata.vhdx') -Force -ErrorAction SilentlyContinue

                    Write-LabStatus -Status WARN -Message "Continuing without LIN1. Create it manually later with Configure-LIN1.ps1"
                }
            }
        }
    }

    # ============================================================
    # WAIT FOR LIN1 to become reachable over SSH
    # ============================================================
    $lin1WaitSectionStart = Get-Date
    if ($IncludeLIN1) {
        $lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
        if ($lin1Vm) {
            if ($lin1Vm.State -ne 'Running') {
                Write-Host "  LIN1 VM is $($lin1Vm.State). Starting..." -ForegroundColor Yellow
                Start-VM -Name 'LIN1'
            }

$lin1WaitMinutes = $LIN1_WaitMinutes
            Write-Host "`n[LIN1] Waiting for unattended Ubuntu install + SSH (up to $lin1WaitMinutes min)..." -ForegroundColor Cyan
            $lin1WaitResult = Wait-LinuxVMReady -VMName 'LIN1' -WaitMinutes $lin1WaitMinutes -DhcpServer 'DC1' -ScopeId $DhcpScopeId
            $lin1Ready = $lin1WaitResult.Ready
            if (-not $lin1Ready) {
                Write-Host "  This usually means Ubuntu autoinstall did not complete. Check LIN1 console boot menu/autoinstall logs." -ForegroundColor Yellow
                if ($lin1WaitResult.LeaseIP) {
                    Write-LabStatus -Status INFO -Message "LIN1 DHCP lease observed at: $($lin1WaitResult.LeaseIP)"
                }
            }
        } else {
            Write-LabStatus -Status WARN -Message "LIN1 VM not found. Skipping LIN1 wait."
        }
    } else {
        Write-Host "`n[LIN1] Skipping LIN1 deployment/config in this run (deferred)." -ForegroundColor Yellow
    }
    $sectionElapsed = (Get-Date) - $lin1WaitSectionStart
    Write-Host "  Section completed in $([int]$sectionElapsed.TotalMinutes)m $($sectionElapsed.Seconds)s" -ForegroundColor DarkGray

    # ============================================================
    # POST-INSTALL: DC1 share + Git
    # ============================================================
    $postInstallSectionStart = Get-Date
    Write-Host "`n[POST] Configuring DC1 share + Git..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Create-LabShare' -ScriptBlock {
        param($SharePath, $ShareName, $GitRepoPath, $DomainName)

        New-Item -Path $SharePath -ItemType Directory -Force | Out-Null
        New-Item -Path $GitRepoPath -ItemType Directory -Force | Out-Null
        New-Item -Path "$SharePath\Transfer" -ItemType Directory -Force | Out-Null
        New-Item -Path "$SharePath\Tools" -ItemType Directory -Force | Out-Null

        $netbios = ($DomainName -split '\.')[0].ToUpper()
        try {
            New-ADGroup -Name 'LabShareUsers' -GroupScope DomainLocal -Path "CN=Users,DC=$($DomainName -replace '\.',',DC=')" -ErrorAction Stop | Out-Null
        } catch {
            Write-Verbose "LabShareUsers group create skipped: $($_.Exception.Message)"
        }

        try {
            Add-ADGroupMember -Identity 'LabShareUsers' -Members 'Domain Users' -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "LabShareUsers add Domain Users skipped: $($_.Exception.Message)"
        }

        try {
            if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
                New-SmbShare -Name $ShareName -Path $SharePath `
                    -FullAccess "$netbios\LabShareUsers", "$netbios\Domain Admins" `
                    -Description 'OpenCode Lab Shared Storage' | Out-Null
            }
        } catch {
            Write-Verbose "SMB share create/check skipped: $($_.Exception.Message)"
        }

        $acl = Get-Acl $SharePath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$netbios\LabShareUsers", 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl $SharePath $acl

        "Share ready"
    } -ArgumentList $SharePath, $ShareName, $GitRepoPath, $DomainName | Out-Null

    # Add domain members to share group (after join)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Add-Clients-To-ShareGroup' -ScriptBlock {
        try {
            Add-ADGroupMember -Identity 'LabShareUsers' -Members 'Win11$' -ErrorAction Stop | Out-Null
            Add-ADGroupMember -Identity 'LabShareUsers' -Members 'Server1$' -ErrorAction SilentlyContinue | Out-Null
        } catch {
            Write-Verbose "LabShareUsers membership update skipped: $($_.Exception.Message)"
        }
    } | Out-Null

    $gitInstallerScriptBlock = {
        param(
            [string]$LocalInstallerPath,
            [string]$GitDownloadUrl
        )

        $result = [pscustomobject]@{ Installed = $false; Message = '' }

        function Invoke-ProcessWithTimeout {
            param(
                [Parameter(Mandatory)][string]$FilePath,
                [Parameter(Mandatory)][string]$Arguments,
                [int]$TimeoutSeconds = 600
            )

            $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow
            $completed = $true
            try {
                Wait-Process -Id $proc.Id -Timeout $TimeoutSeconds -ErrorAction Stop
            } catch {
                $completed = $false
            }

            if (-not $completed) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                return $null
            }

            $proc.Refresh()
            return $proc.ExitCode
        }

        if (Get-Command git -ErrorAction SilentlyContinue) {
            $result.Installed = $true
            $result.Message = 'Git already installed.'
            return $result
        }

        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            $wingetPath = if (-not [string]::IsNullOrWhiteSpace($winget.Source) -and (Test-Path $winget.Source)) { $winget.Source } else { 'winget' }
            $wingetExit = $null
            try {
                $wingetExit = Invoke-ProcessWithTimeout -FilePath $wingetPath -Arguments 'install --id Git.Git --accept-package-agreements --accept-source-agreements --silent --disable-interactivity' -TimeoutSeconds 180
            } catch {
                $result.Message = "winget install invocation failed: $($_.Exception.Message). Trying fallback installers."
            }
            if ((Get-Command git -ErrorAction SilentlyContinue) -or $wingetExit -eq 0) {
                $result.Installed = $true
                $result.Message = 'Git installed via winget.'
                return $result
            }
            if ($null -eq $wingetExit -and [string]::IsNullOrWhiteSpace($result.Message)) {
                $result.Message = 'winget install timed out; trying fallback installers.'
            }
        }

        if (Test-Path $LocalInstallerPath) {
            $localExit = Invoke-ProcessWithTimeout -FilePath $LocalInstallerPath -Arguments '/VERYSILENT /NORESTART /COMPONENTS="gitlfs"' -TimeoutSeconds 600
            if ((Get-Command git -ErrorAction SilentlyContinue) -or $localExit -eq 0) {
                $result.Installed = $true
                $result.Message = 'Git installed from local cached installer.'
                return $result
            }
        }

        $dnsProbe = Resolve-DnsName -Name 'release-assets.githubusercontent.com' -Type A -ErrorAction SilentlyContinue
        if (-not $dnsProbe) {
            if ([string]::IsNullOrWhiteSpace($result.Message)) {
                $result.Message = 'External DNS not resolving release-assets.githubusercontent.com; skipping web installer.'
            }
            return $result
        }

        $gitInstaller = "$env:TEMP\GitInstall.exe"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        for ($attempt = 1; $attempt -le 2; $attempt++) {
            try {
                Invoke-WebRequest -Uri $GitDownloadUrl -OutFile $gitInstaller -UseBasicParsing -TimeoutSec 25
                $webExit = Invoke-ProcessWithTimeout -FilePath $gitInstaller -Arguments '/VERYSILENT /NORESTART /COMPONENTS="gitlfs"' -TimeoutSeconds 600
                if ((Get-Command git -ErrorAction SilentlyContinue) -or $webExit -eq 0) {
                    $result.Installed = $true
                    $result.Message = "Git installed via direct download (attempt $attempt)."
                    break
                }
            } catch {
                $result.Message = "Git download/install attempt $attempt failed: $($_.Exception.Message)"
                Start-Sleep -Seconds (5 * $attempt)
            }
        }

        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
        if (-not $result.Installed -and [string]::IsNullOrWhiteSpace($result.Message)) {
            $result.Message = 'Git installer path exhausted (winget/local/web).'
        }

        return $result
    }

    # Install Git on DC1 (winget preferred, with offline/web fallback)
    try {
        $dc1GitResults = @(Invoke-LabCommand -ComputerName 'DC1' -PassThru -ActivityName 'Install-Git-DC1' -ScriptBlock $gitInstallerScriptBlock -ArgumentList 'C:\LabSources\SoftwarePackages\Git\Git-2.47.1.2-64-bit.exe', 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe')

        $dc1GitResult = @($dc1GitResults | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Installed' } | Select-Object -Last 1)

        if ($dc1GitResult.Count -gt 0 -and $dc1GitResult[0].Installed) {
            Write-LabStatus -Status OK -Message "$($dc1GitResult[0].Message)"
        } elseif ($dc1GitResult.Count -gt 0) {
            $msg = if ($dc1GitResult[0].Message) { $dc1GitResult[0].Message } else { 'Unknown Git install failure on DC1.' }
            Write-LabStatus -Status WARN -Message "$msg"
            Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on DC1."
        } else {
            Write-LabStatus -Status WARN -Message "Git installation step on DC1 returned no structured result."
            Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on DC1."
        }
    } catch {
        Write-LabStatus -Status WARN -Message "Git installation step on DC1 failed: $($_.Exception.Message)"
        Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on DC1."
    }

    # ============================================================
    # DC1: OpenSSH Server + allow key auth for admins (Host -> DC1)
    # ============================================================
    Write-Host "`n[POST] Configuring DC1 OpenSSH..." -ForegroundColor Cyan
    $dc1SshReady = $false
    try {
        $dc1SshResult = Invoke-LabCommand -ComputerName 'DC1' -PassThru -ActivityName 'Install-OpenSSH-DC1' -ScriptBlock {
            $result = @{ Ready = $false; Message = '' }
            try {
                Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
            } catch {
                $result.Message = "OpenSSH server capability install failed: $($_.Exception.Message)"
                return $result
            }

            try {
                Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
                Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
                Start-Service sshd -ErrorAction Stop
                New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
                    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
                    -PropertyType String -Force | Out-Null
                New-NetFirewallRule -DisplayName 'OpenSSH Server (TCP 22)' -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
                $result.Ready = $true
                $result.Message = 'OpenSSH configured successfully.'
            } catch {
                $result.Message = "OpenSSH post-install configuration failed: $($_.Exception.Message)"
            }
            return $result
        }

        if ($dc1SshResult -and $dc1SshResult.Ready) {
            $dc1SshReady = $true
            Write-LabStatus -Status OK -Message "DC1 OpenSSH configured"
        } else {
            $msg = if ($dc1SshResult -and $dc1SshResult.Message) { $dc1SshResult.Message } else { 'Unknown OpenSSH configuration failure.' }
            Write-LabStatus -Status WARN -Message "$msg"
            Write-LabStatus -Status WARN -Message "Continuing deployment without DC1 SSH key bootstrap."
        }
    } catch {
        Write-LabStatus -Status WARN -Message "DC1 OpenSSH setup failed: $($_.Exception.Message)"
        Write-LabStatus -Status WARN -Message "Continuing deployment without DC1 SSH key bootstrap."
    }

    if ($dc1SshReady) {
        Copy-LabFileItem -Path $SSHPublicKey -ComputerName 'DC1' -DestinationFolderPath 'C:\ProgramData\ssh'

        Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Authorize-HostKey-DC1' -ScriptBlock {
            param($PubKeyFileName)
            $authKeysFile = 'C:\ProgramData\ssh\administrators_authorized_keys'
            $pubKeyFile   = "C:\ProgramData\ssh\$PubKeyFileName"
            if (Test-Path $pubKeyFile) {
                Get-Content $pubKeyFile | Add-Content $authKeysFile -Force
                icacls $authKeysFile /inheritance:r /grant "SYSTEM:(F)" /grant "BUILTIN\Administrators:(F)" | Out-Null
                Remove-Item $pubKeyFile -Force -ErrorAction SilentlyContinue
            }
        } -ArgumentList $HostPublicKeyFileName | Out-Null
    }

    # DC1: WinRM HTTPS + ICMP (useful for remote management)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Configure-WinRM-HTTPS-DC1' -ScriptBlock {
        $fqdn = "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
        $cert = New-SelfSignedCertificate -DnsName $fqdn, $env:COMPUTERNAME -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)

        Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
            ForEach-Object { Remove-Item $_.PSPath -Recurse -Force }

        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

        New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName 'ICMPv4 Allow' -Protocol ICMPv4 -IcmpType 8 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue | Out-Null
    } | Out-Null


    # ============================================================
    # Server1: keep as fresh Windows Server 2019 member server
    # ============================================================
    Write-Host "`n[POST] Server1 baseline..." -ForegroundColor Cyan
    Write-LabStatus -Status OK -Message "Server1 left as a clean Windows Server 2019 VM (no WSUS role installed)."
    Write-LabStatus -Status INFO -Message "Install additional roles/features on Server1 manually when ready."

    # ============================================================
    # Win11: client basics (RSAT + drive map)
    # ============================================================
    Write-Host "`n[POST] Configuring Win11..." -ForegroundColor Cyan

    # RSAT install: domain GP may redirect Windows Update through DC1 (no WSUS),
    # causing "Access is denied" COMException. Temporarily bypass the WSUS policy.
    try {
        Invoke-LabCommand -ComputerName 'Win11' -ActivityName 'Install-RSAT-Win11' -ScriptBlock {
            $wuAuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            $originalUseWU = $null

            # Save and bypass WSUS redirect if present
            if (Test-Path $wuAuPath) {
                $originalUseWU = (Get-ItemProperty -Path $wuAuPath -Name UseWUServer -ErrorAction SilentlyContinue).UseWUServer
                if ($null -ne $originalUseWU) {
                    Set-ItemProperty -Path $wuAuPath -Name UseWUServer -Value 0 -ErrorAction SilentlyContinue
                    Restart-Service wuauserv -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 5
                }
            }

            try {
                $rsatCapabilities = @(
                    'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0',
                    'Rsat.Dns.Tools~~~~0.0.1.0',
                    'Rsat.DHCP.Tools~~~~0.0.1.0',
                    'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
                )
                foreach ($cap in $rsatCapabilities) {
                    $state = (Get-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue).State
                    if ($state -ne 'Installed') {
                        Add-WindowsCapability -Online -Name $cap -ErrorAction Stop | Out-Null
                    }
                }
                Set-Service -Name AppIDSvc -StartupType Automatic
                Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
            }
            finally {
                # Restore original WSUS setting
                if ($null -ne $originalUseWU) {
                    Set-ItemProperty -Path $wuAuPath -Name UseWUServer -Value $originalUseWU -ErrorAction SilentlyContinue
                    Restart-Service wuauserv -Force -ErrorAction SilentlyContinue
                }
            }
        } | Out-Null
        Write-LabStatus -Status OK -Message "RSAT capabilities installed on Win11"
    }
    catch {
        Write-LabStatus -Status WARN -Message "RSAT installation failed: $($_.Exception.Message)"
        Write-LabStatus -Status WARN -Message "Win11 will work without RSAT. Install manually later if needed."
    }

    Invoke-LabCommand -ComputerName 'Win11' -ActivityName 'Map-LabShare' -ScriptBlock {
        param($ShareName)
        net use L: "\\DC1\$ShareName" /persistent:yes 2>$null
    } -ArgumentList $ShareName | Out-Null

    # Win11: WinRM HTTPS + ICMP
    Invoke-LabCommand -ComputerName 'Win11' -ActivityName 'Configure-WinRM-HTTPS-Win11' -ScriptBlock {
        $fqdn = "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
        $cert = New-SelfSignedCertificate -DnsName $fqdn, $env:COMPUTERNAME -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)

        Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
            ForEach-Object { Remove-Item $_.PSPath -Recurse -Force }

        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

        New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName 'ICMPv4 Allow' -Protocol ICMPv4 -IcmpType 8 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue | Out-Null
    } | Out-Null

    # Win11: Git (winget preferred, with offline/web fallback)
    try {
        $win11GitResults = @(Invoke-LabCommand -ComputerName 'Win11' -PassThru -ActivityName 'Install-Git-Win11' -ScriptBlock $gitInstallerScriptBlock -ArgumentList 'C:\LabSources\SoftwarePackages\Git\Git-2.47.1.2-64-bit.exe', 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe')

        $win11GitResult = @($win11GitResults | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Installed' } | Select-Object -Last 1)

        if ($win11GitResult.Count -gt 0 -and $win11GitResult[0].Installed) {
            Write-LabStatus -Status OK -Message "$($win11GitResult[0].Message)"
        } elseif ($win11GitResult.Count -gt 0) {
            $msg = if ($win11GitResult[0].Message) { $win11GitResult[0].Message } else { 'Unknown Git install failure on Win11.' }
            Write-LabStatus -Status WARN -Message "$msg"
            Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on Win11."
        } else {
            Write-LabStatus -Status WARN -Message "Git installation step on Win11 returned no structured result."
            Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on Win11."
        }
    } catch {
        Write-LabStatus -Status WARN -Message "Git installation step on Win11 failed: $($_.Exception.Message)"
        Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on Win11."
    }


    # ============================================================
    # LIN1: deterministic user, SSH keys, static IP, SMB mount, dev tools
    # ============================================================
    if ($IncludeLIN1 -and $lin1Ready) {
    Write-Host "`n[POST] Configuring LIN1 (Ubuntu dev host)..." -ForegroundColor Cyan

    $netbios = ($DomainName -split '\.')[0].ToUpper()
    $linUser = $LabInstallUser
    $linHome = "/home/$linUser"


    $escapedPassword = $AdminPassword -replace "'", "'\\''"

    $lin1ScriptContent = Get-Content (Join-Path $ScriptDir 'Scripts\Configure-LIN1.sh') -Raw
    Copy-LabFileItem -Path $SSHPublicKey -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

    $lin1Vars = @{
        LIN_USER = $linUser
        LIN_HOME = $linHome
        DOMAIN = $DomainName
        NETBIOS = $netbios
        SHARE = $ShareName
        PASS = $escapedPassword
        GATEWAY = $GatewayIp
        DNS = $DnsIp
        STATIC_IP = $LIN1_Ip
        HOST_PUBKEY = $HostPublicKeyFileName
    }

    Invoke-BashOnLinuxVM -VMName 'LIN1' -BashScript $lin1ScriptContent -ActivityName 'Configure-LIN1' -Variables $lin1Vars | Out-Null
    } else {
        Write-LabStatus -Status WARN -Message "Skipping LIN1 post-config (not included or not reachable)."
    }

    if ($IncludeLIN1 -and $lin1Ready) {
        Write-Host "`n[LIN1] Finalizing boot media (detach installer + seed disk)..." -ForegroundColor Cyan
        Finalize-LinuxInstallMedia -VMName 'LIN1' | Out-Null
    }
    $sectionElapsed = (Get-Date) - $postInstallSectionStart
    Write-Host "  Section completed in $([int]$sectionElapsed.TotalMinutes)m $($sectionElapsed.Seconds)s" -ForegroundColor DarkGray

    # ============================================================
    # SNAPSHOT
    # ============================================================
    Write-Host "`n[SNAPSHOT] Creating 'LabReady' checkpoint..." -ForegroundColor Cyan
    Checkpoint-LabVM -All -SnapshotName 'LabReady' | Out-Null
    Write-Host "  Checkpoint created." -ForegroundColor Green

    $deployElapsed = (Get-Date) - $deployStartTime
    Write-Host "  Total deployment time: $([int]$deployElapsed.TotalMinutes)m $($deployElapsed.Seconds)s" -ForegroundColor Cyan

    # ============================================================
    # SUMMARY
    # ============================================================
    Write-Host "`n[SUMMARY]" -ForegroundColor Cyan
    Write-Host "  DC1:  $DC1_Ip" -ForegroundColor Gray
    Write-Host "  Server1: $Server1_Ip" -ForegroundColor Gray
    Write-Host "  Win11:  $Win11_Ip" -ForegroundColor Gray
    if ($IncludeLIN1 -and $lin1Ready) {
        Write-Host "  LIN1: $LIN1_Ip (static configured by script)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Host -> LIN1 SSH:" -ForegroundColor Cyan
        Write-Host "    ssh -o IdentitiesOnly=yes -i $SSHPrivateKey $LabInstallUser@$LIN1_Ip" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  If you see the 'REMOTE HOST IDENTIFICATION HAS CHANGED' warning after a rebuild:" -ForegroundColor Cyan
        Write-Host "    ssh-keygen -R $LIN1_Ip" -ForegroundColor Yellow
    } else {
        Write-Host "  Linux nodes: not included in this topology" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "DONE. Log saved to: $logFile" -ForegroundColor Green
}
catch {
    Write-Host "`nDEPLOYMENT FAILED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nSee log: $logFile" -ForegroundColor Yellow
    throw
}
finally {
    Stop-Transcript | Out-Null
}
