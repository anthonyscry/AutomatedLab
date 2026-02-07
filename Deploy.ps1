# Deploy-OpenCodeLab-Slim.ps1 - Rebuildable 3-VM OpenCode Development Lab (AutomatedLab)
# Builds DC1 (AD/DNS/DHCP/CA), WS1 (Win11), LIN1 (Ubuntu 24.04) on Hyper-V
# Requires: AutomatedLab module, Hyper-V, ISOs in C:\LabSources\ISOs

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$ForceRebuild,
    [string]$AdminPassword = 'Server123!'
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
$LabInstallUser = 'install'
if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    if ($env:OPENCODELAB_ADMIN_PASSWORD) {
        $AdminPassword = $env:OPENCODELAB_ADMIN_PASSWORD
    }
}
if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    $AdminPassword = 'Server123!'
    Write-Host "  [WARN] AdminPassword was empty. Falling back to default password." -ForegroundColor Yellow
}

$IsoPath        = "$LabSourcesRoot\ISOs"
$HostPublicKeyFileName = [System.IO.Path]::GetFileName($SSHPublicKey)

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
$logFile = "$logDir\Deploy-OpenCodeLab-Slim_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
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

    # Remove existing lab if present
    if (Get-Lab -List | Where-Object { $_ -eq $LabName }) {
        Write-Host "  Lab '$LabName' already exists." -ForegroundColor Yellow
        $allowRebuild = $false
        if ($ForceRebuild -or $NonInteractive) {
            $allowRebuild = $true
        } else {
            $response = Read-Host "  Remove and rebuild? (y/n)"
            if ($response -eq 'y') { $allowRebuild = $true }
        }

        if ($allowRebuild) {
            Remove-Lab -Name $LabName -Confirm:$false
            Write-Host "  Removed existing lab." -ForegroundColor Green
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
    Write-Host "`n[LAB] Defining lab '$LabName'..." -ForegroundColor Cyan

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

    # Ensure vSwitch + NAT exist (idempotent)
    Write-Host "  Ensuring Hyper-V lab switch + NAT ($LabSwitch / $AddressSpace)..." -ForegroundColor Yellow

    if (-not (Get-VMSwitch -Name $LabSwitch -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name $LabSwitch -SwitchType Internal | Out-Null
        Write-Host "    [OK] Created VMSwitch: $LabSwitch (Internal)" -ForegroundColor Green
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
        Write-Host "    [OK] Set host gateway IP: $GatewayIp on $ifAlias" -ForegroundColor Green
    } else {
        Write-Host "    [OK] Host gateway IP already set: $GatewayIp" -ForegroundColor Green
    }

    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-Host "    [OK] Created NAT: $NatName for $AddressSpace" -ForegroundColor Green
    } elseif ($nat.InternalIPInterfaceAddressPrefix -ne $AddressSpace) {
        Write-Host "    [WARN] NAT '$NatName' exists with prefix '$($nat.InternalIPInterfaceAddressPrefix)'. Recreating..." -ForegroundColor Yellow
        Remove-NetNat -Name $NatName -Confirm:$false | Out-Null
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-Host "    [OK] Recreated NAT: $NatName for $AddressSpace" -ForegroundColor Green
    } else {
        Write-Host "    [OK] NAT exists: $NatName" -ForegroundColor Green
    }

    # Register network with AutomatedLab
    Add-LabVirtualNetworkDefinition -Name $LabSwitch -AddressSpace $AddressSpace -HyperVProperties @{ SwitchType = 'Internal' }

    # Use the deterministic install credential everywhere
    Set-LabInstallationCredential -Username $LabInstallUser -Password $AdminPassword
    Add-LabDomainDefinition -Name $DomainName -AdminUser $LabInstallUser -AdminPassword $AdminPassword

    # ============================================================
    # MACHINE DEFINITIONS
    # ============================================================
    Write-Host "`n[LAB] Defining core machines (DC1 + WS1)..." -ForegroundColor Cyan

    Add-LabMachineDefinition -Name 'DC1' `
        -Roles RootDC, CaRoot `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $DC1_Ip -Gateway $GatewayIp -DnsServer1 $DC1_Ip `
        -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
        -Memory $DC_Memory -MinMemory $DC_MinMemory -MaxMemory $DC_MaxMemory `
        -Processors $DC_Processors

    Add-LabMachineDefinition -Name 'WS1' `
        -DomainName $DomainName `
        -Network $LabSwitch `
        -IpAddress $WS1_Ip -Gateway $GatewayIp -DnsServer1 $DnsIp `
        -OperatingSystem 'Windows 11 Enterprise Evaluation' `
        -Memory $CL_Memory -MinMemory $CL_MinMemory -MaxMemory $CL_MaxMemory `
        -Processors $CL_Processors

    # ============================================================
    # INSTALL LAB STAGE 1 (Windows only)
    # Keep Linux out of stage 1 so DC1 can bring DHCP online first.
    # This prevents Ubuntu from dropping into interactive setup when
    # no DHCP server exists yet on the internal switch.
    # ============================================================
    Write-Host "`n[INSTALL] Installing core machines (DC1 + WS1)..." -ForegroundColor Cyan

    $installLabFailed = $false
    try {
        Install-Lab
    } catch {
        Write-Host "  [WARN] Install-Lab encountered an error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Will attempt to validate and recover DC1 AD DS installation..." -ForegroundColor Yellow
        $installLabFailed = $true
    }

    # ============================================================
    # STAGE 1 AD DS VALIDATION: Verify DC promotion succeeded
    # ============================================================
    Write-Host "`n[VALIDATE] Verifying AD DS promotion on DC1..." -ForegroundColor Cyan

    # Ensure DC1 VM is running
    $dc1Vm = Hyper-V\Get-VM -Name 'DC1' -ErrorAction SilentlyContinue
    if ($dc1Vm -and $dc1Vm.State -ne 'Running') {
        Write-Host "  DC1 VM is $($dc1Vm.State). Starting..." -ForegroundColor Yellow
        Start-VM -Name 'DC1'
        Start-Sleep -Seconds 30
    }

    # Wait for WinRM to become reachable
    Write-Host "  Waiting for WinRM on DC1..." -ForegroundColor Gray
    $winrmReady = $false
    for ($w = 1; $w -le 12; $w++) {
        $wrmCheck = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($wrmCheck.TcpTestSucceeded) { $winrmReady = $true; break }
        Write-Host "    WinRM attempt $w/12..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
    if (-not $winrmReady) {
        throw "DC1 WinRM (port 5985) is unreachable. Cannot validate AD DS installation."
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
        Write-Host "  [OK] DC1 is a domain controller for '$($adStatus.ForestName)'" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] AD DS is NOT operational on DC1 after Install-Lab." -ForegroundColor Yellow
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
            Write-Host "    [OK] AD DS feature installed" -ForegroundColor Green
        }

        # Step 2: Run Install-ADDSForest
        $netbiosDomain = ($DomainName -split '\.')[0].ToUpper()
        Write-Host "    Promoting DC1 to domain controller for '$DomainName' (NetBIOS: $netbiosDomain)..." -ForegroundColor Yellow

        Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Recovery-ADDSForest' -ScriptBlock {
            param($Domain, $Netbios, $Pwd)
            $securePwd = ConvertTo-SecureString $Pwd -AsPlainText -Force
            Install-ADDSForest `
                -DomainName $Domain `
                -DomainNetbiosName $Netbios `
                -SafeModeAdministratorPassword $securePwd `
                -InstallDns:$true `
                -NoRebootOnCompletion:$false `
                -Force `
                -WarningAction SilentlyContinue
        } -ArgumentList $DomainName, $netbiosDomain, $AdminPassword | Out-Null

        Write-Host "    [OK] Install-ADDSForest initiated. Waiting for DC1 to restart..." -ForegroundColor Green

        # Step 3: Wait for DC1 to go offline and come back
        Start-Sleep -Seconds 60

        $dc1Back = $false
        $restartDeadline = [datetime]::Now.AddMinutes(15)
        while ([datetime]::Now -lt $restartDeadline) {
            $rCheck = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($rCheck.TcpTestSucceeded) { $dc1Back = $true; break }
            Write-Host "    Waiting for DC1 to come back online..." -ForegroundColor Gray
            Start-Sleep -Seconds 15
        }
        if (-not $dc1Back) {
            throw "DC1 did not come back online after AD DS recovery promotion. Check the VM manually."
        }

        # Step 4: Wait for ADWS and NTDS to start
        Write-Host "    Waiting for AD services to initialize..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60

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
            throw "AD Web Services did not start on DC1 after recovery. Check DC1 event logs (Event Viewer > Directory Services)."
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
            Write-Host "  [OK] Recovery successful! DC1 is domain controller for '$($finalAd.ForestName)'" -ForegroundColor Green
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
        Write-Host "  [WARN] Host gateway IP $GatewayIp missing on $ifAlias after Install-Lab. Re-applying..." -ForegroundColor Yellow
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIp -PrefixLength 24 | Out-Null
        Write-Host "  [OK] Re-applied host gateway IP: $GatewayIp" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Host gateway IP intact: $GatewayIp" -ForegroundColor Green
    }

    # 2. Verify NAT still exists
    $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        Write-Host "  [WARN] NAT '$NatName' missing after Install-Lab. Recreating..." -ForegroundColor Yellow
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-Host "  [OK] Recreated NAT: $NatName" -ForegroundColor Green
    } else {
        Write-Host "  [OK] NAT intact: $NatName" -ForegroundColor Green
    }

    # 3. Ping DC1 to verify L3 connectivity
    $pingOk = Test-Connection -ComputerName $DC1_Ip -Count 3 -Quiet -ErrorAction SilentlyContinue
    if (-not $pingOk) {
        throw "Cannot ping DC1 ($DC1_Ip) from host after Stage 1. Check vSwitch '$LabSwitch' and host adapter '$ifAlias'. Aborting before Stage 2."
    }
    Write-Host "  [OK] DC1 ($DC1_Ip) responds to ping" -ForegroundColor Green

    # 4. Verify WinRM connectivity (this is what AutomatedLab uses internally)
    $winrmOk = Test-NetConnection -ComputerName $DC1_Ip -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if (-not $winrmOk.TcpTestSucceeded) {
        Write-Host "  [WARN] WinRM port 5985 not reachable on DC1 ($DC1_Ip). AD may still be starting." -ForegroundColor Yellow
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
    Write-Host "  [OK] WinRM reachable on DC1 ($DC1_Ip):5985" -ForegroundColor Green
    Write-Host "  [OK] Stage 1 validation passed - proceeding to DHCP + Stage 2" -ForegroundColor Green

    # ============================================================
    # DC1: DHCP ROLE + SCOPE
    # ============================================================
    Write-Host "`n[DC1] Enabling DHCP for Linux installs (prevents Ubuntu DHCP/autoconfig failure)..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Install-DHCP-Role' -ScriptBlock {
        param($ScopeId, $StartRange, $EndRange, $Mask, $Router, $Dns, $DnsDomain)

        # Install DHCP role
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null

        # Authorize DHCP in AD (ignore if already authorized)
        try {
            if ($Dns) { Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -IPAddress $Dns | Out-Null }
        } catch {}

        # Create scope if missing
        $existing = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId.IPAddressToString -eq $ScopeId }
        if (-not $existing) {
            Add-DhcpServerv4Scope -Name "OpenCodeLab" -StartRange $StartRange -EndRange $EndRange -SubnetMask $Mask -State Active | Out-Null
        }

        # Options
        Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -DnsServer @($Dns,'1.1.1.1') -DnsDomain $DnsDomain | Out-Null

        Restart-Service DHCPServer -ErrorAction SilentlyContinue
        Set-Service DHCPServer -StartupType Automatic

        "DHCP scope ready"
    } -ArgumentList $DhcpScopeId, $DhcpStart, $DhcpEnd, $DhcpMask, $GatewayIp, $DnsIp, $DomainName | Out-Null

    Write-Host "  [OK] DHCP scope configured: $DhcpScopeId ($DhcpStart - $DhcpEnd)" -ForegroundColor Green

    # ============================================================
    # LIN1 STAGE 2: define/install Linux only after DHCP is live.
    # This keeps Ubuntu 24.04 autoinstall fully unattended.
    # ============================================================
    Write-Host "`n[LIN1] Defining LIN1 after DHCP is available..." -ForegroundColor Cyan
    Add-LabMachineDefinition -Name 'LIN1' `
        -Network $LabSwitch `
        -OperatingSystem 'Ubuntu-Server 24.04.3 LTS "Noble Numbat"' `
        -Memory $UBU_Memory -MinMemory $UBU_MinMemory -MaxMemory $UBU_MaxMemory `
        -Processors $UBU_Processors

    Write-Host "[LIN1] Installing LIN1 (unattended Ubuntu via AutomatedLab)..." -ForegroundColor Cyan
    try {
        Install-Lab
    } catch {
        Write-Host "  [WARN] Install-Lab reported during LIN1 stage: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Continuing with explicit LIN1 readiness checks..." -ForegroundColor Yellow
    }

    # ============================================================
    # WAIT FOR LIN1 to become reachable over SSH
    # ============================================================
    $lin1Vm = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
    if ($lin1Vm) {
        if ($lin1Vm.State -ne 'Running') {
            Write-Host "  LIN1 VM is $($lin1Vm.State). Starting..." -ForegroundColor Yellow
            Start-VM -Name 'LIN1'
        }

        $lin1WaitMinutes = 30
        Write-Host "`n[LIN1] Waiting for unattended Ubuntu install + SSH (up to $lin1WaitMinutes min)..." -ForegroundColor Cyan
        $lin1Ready = $false
        $lin1Deadline = [datetime]::Now.AddMinutes($lin1WaitMinutes)
        $lastKnownIp = ''
        while ([datetime]::Now -lt $lin1Deadline) {
            $lin1Ips = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
                Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }
            if ($lin1Ips) {
                $lin1DhcpIp = $lin1Ips | Select-Object -First 1
                $lastKnownIp = $lin1DhcpIp
                $sshCheck = Test-NetConnection -ComputerName $lin1DhcpIp -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                if ($sshCheck.TcpTestSucceeded) {
                    $lin1Ready = $true
                    Write-Host "  [OK] LIN1 SSH is reachable at $lin1DhcpIp" -ForegroundColor Green
                    break
                }
            }
            Start-Sleep -Seconds 30
            if ($lastKnownIp) {
                Write-Host "    LIN1 has IP ($lastKnownIp), waiting for SSH..." -ForegroundColor Gray
            } else {
                Write-Host "    Still waiting for LIN1 DHCP lease..." -ForegroundColor Gray
            }
        }
        if (-not $lin1Ready) {
            Write-Host "  [WARN] LIN1 did not become SSH-reachable after $lin1WaitMinutes min." -ForegroundColor Yellow
            Write-Host "  This usually means Ubuntu autoinstall did not complete. Check LIN1 console boot menu/autoinstall logs." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARN] LIN1 VM not found. Skipping LIN1 wait." -ForegroundColor Yellow
    }

    # ============================================================
    # POST-INSTALL: DC1 share + Git
    # ============================================================
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
        } catch {}

        try { Add-ADGroupMember -Identity 'LabShareUsers' -Members 'Domain Users' -ErrorAction SilentlyContinue } catch {}

        try {
            if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
                New-SmbShare -Name $ShareName -Path $SharePath `
                    -FullAccess "$netbios\LabShareUsers", "$netbios\Domain Admins" `
                    -Description 'OpenCode Lab Shared Storage' | Out-Null
            }
        } catch {}

        $acl = Get-Acl $SharePath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$netbios\LabShareUsers", 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl $SharePath $acl

        "Share ready"
    } -ArgumentList $SharePath, $ShareName, $GitRepoPath, $DomainName | Out-Null

    # Add WS1$ to share group (after join)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Add-WS1-To-ShareGroup' -ScriptBlock {
        try { Add-ADGroupMember -Identity 'LabShareUsers' -Members 'WS1$' -ErrorAction Stop | Out-Null } catch {}
    } | Out-Null

    # Install Git on DC1 (winget if available, else direct)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Install-Git-DC1' -ScriptBlock {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            winget install --id Git.Git --accept-package-agreements --accept-source-agreements --silent 2>$null
        } else {
            $gitUrl = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe'
            $gitInstaller = "$env:TEMP\GitInstall.exe"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
            Start-Process -FilePath $gitInstaller -ArgumentList '/VERYSILENT /NORESTART /COMPONENTS="gitlfs"' -Wait -NoNewWindow
            Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null

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
            Write-Host "  [OK] DC1 OpenSSH configured" -ForegroundColor Green
        } else {
            $msg = if ($dc1SshResult -and $dc1SshResult.Message) { $dc1SshResult.Message } else { 'Unknown OpenSSH configuration failure.' }
            Write-Host "  [WARN] $msg" -ForegroundColor Yellow
            Write-Host "  [WARN] Continuing deployment without DC1 SSH key bootstrap." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] DC1 OpenSSH setup failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  [WARN] Continuing deployment without DC1 SSH key bootstrap." -ForegroundColor Yellow
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
    # WS1: client basics (RSAT + drive map)
    # ============================================================
    Write-Host "`n[POST] Configuring WS1..." -ForegroundColor Cyan

    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Install-RSAT-WS1' -ScriptBlock {
        $rsatCapabilities = @(
            'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0',
            'Rsat.Dns.Tools~~~~0.0.1.0',
            'Rsat.DHCP.Tools~~~~0.0.1.0',
            'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
        )
        foreach ($cap in $rsatCapabilities) {
            $state = (Get-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue).State
            if ($state -ne 'Installed') { Add-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue | Out-Null }
        }
        Set-Service -Name AppIDSvc -StartupType Automatic
        Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    } | Out-Null

    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Map-LabShare' -ScriptBlock {
        param($ShareName)
        net use L: "\\DC1\$ShareName" /persistent:yes 2>$null
    } -ArgumentList $ShareName | Out-Null

    # WS1: WinRM HTTPS + ICMP
    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Configure-WinRM-HTTPS-WS1' -ScriptBlock {
        $fqdn = "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
        $cert = New-SelfSignedCertificate -DnsName $fqdn, $env:COMPUTERNAME -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)

        Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
            ForEach-Object { Remove-Item $_.PSPath -Recurse -Force }

        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

        New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName 'ICMPv4 Allow' -Protocol ICMPv4 -IcmpType 8 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue | Out-Null
    } | Out-Null

    # WS1: Git (winget)
    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'Install-Git-WS1' -ScriptBlock {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            winget install --id Git.Git --accept-package-agreements --accept-source-agreements --silent 2>$null
        }
    } | Out-Null


    # ============================================================
    # LIN1: deterministic user, SSH keys, static IP, SMB mount, dev tools
    # ============================================================
    Write-Host "`n[POST] Configuring LIN1 (Ubuntu dev host)..." -ForegroundColor Cyan

    $netbios = ($DomainName -split '\.')[0].ToUpper()
    $linUser = $LabInstallUser
    $linHome = "/home/$linUser"


    $escapedPassword = $AdminPassword -replace "'", "'\\''"

    # Use non-interpolating here-string to avoid PowerShell eating bash variables
    $lin1ScriptContent = @'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

# Pick the first non-lo interface (installer often shows eth0, but this is safer)
IFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
if [ -z "$IFACE" ]; then IFACE="eth0"; fi

LIN_USER="__LIN_USER__"
LIN_HOME="__LIN_HOME__"
DOMAIN="__DOMAIN__"
NETBIOS="__NETBIOS__"
SHARE="__SHARE__"
PASS='__PASS__'
GATEWAY="__GATEWAY__"
DNS="__DNS__"
STATIC_IP="__STATIC_IP__"
HOST_PUBKEY_FILE="__HOST_PUBKEY__"

echo "[LIN1] Updating packages..."
$SUDO apt-get update -qq

echo "[LIN1] Installing base tools + OpenSSH..."
$SUDO apt-get install -y -qq \
  openssh-server git curl wget jq cifs-utils net-tools build-essential python3 python3-pip \
  nodejs npm 2>/dev/null || true

$SUDO systemctl enable --now ssh || true

# Ensure SSH allows password auth (optional; helps if you ever need it)
$SUDO tee /etc/ssh/sshd_config.d/99-opencodelab.conf >/dev/null <<'SSHEOF'
PasswordAuthentication yes
PubkeyAuthentication yes
SSHEOF
$SUDO systemctl restart ssh || true

echo "[LIN1] Setting up SSH authorized_keys for ${LIN_USER}..."
mkdir -p "$LIN_HOME/.ssh"
chmod 700 "$LIN_HOME/.ssh"
touch "$LIN_HOME/.ssh/authorized_keys"
chmod 600 "$LIN_HOME/.ssh/authorized_keys"

if [ -f "/tmp/$HOST_PUBKEY_FILE" ]; then
  cat "/tmp/$HOST_PUBKEY_FILE" >> "$LIN_HOME/.ssh/authorized_keys" || true
fi

chown -R "${LIN_USER}:${LIN_USER}" "$LIN_HOME/.ssh"

echo "[LIN1] Generating local SSH keypair (LIN1->DC1)..."
sudo -u "$LIN_USER" bash -lc 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "LIN1-to-DC1"'

echo "[LIN1] Configuring SMB mount..."
$SUDO mkdir -p /mnt/labshare
CREDS_FILE="/etc/opencodelab-labshare.cred"
if [ ! -f "$CREDS_FILE" ]; then
  $SUDO tee "$CREDS_FILE" >/dev/null <<CREDEOF
username=$LIN_USER
password=$PASS
domain=$NETBIOS
CREDEOF
  $SUDO chmod 600 "$CREDS_FILE"
fi
FSTAB_ENTRY="//DC1.$DOMAIN/$SHARE /mnt/labshare cifs credentials=$CREDS_FILE,iocharset=utf8,_netdev 0 0"
if ! grep -qF "DC1.$DOMAIN/$SHARE" /etc/fstab 2>/dev/null; then
  echo "$FSTAB_ENTRY" | $SUDO tee -a /etc/fstab >/dev/null
fi
$SUDO mount -a 2>/dev/null || true

echo "[LIN1] Pinning static IP ($STATIC_IP) for stable SSH..."
$SUDO tee /etc/netplan/99-opencodelab-static.yaml >/dev/null <<NETEOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [$STATIC_IP/24]
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS, 1.1.1.1]
NETEOF

# Apply netplan in the background so we don't hang the remote session mid-flight
(sleep 2; $SUDO netplan apply) >/dev/null 2>&1 &

echo "[LIN1] Done."
'@
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

    Invoke-BashOnLIN1 -BashScript $lin1ScriptContent -ActivityName 'Configure-LIN1' -Variables $lin1Vars | Out-Null

    # ============================================================
    # SNAPSHOT
    # ============================================================
    Write-Host "`n[SNAPSHOT] Creating 'LabReady' checkpoint..." -ForegroundColor Cyan
    Checkpoint-LabVM -All -SnapshotName 'LabReady' | Out-Null
    Write-Host "  Checkpoint created." -ForegroundColor Green

    # ============================================================
    # SUMMARY
    # ============================================================
    Write-Host "`n[SUMMARY]" -ForegroundColor Cyan
    Write-Host "  DC1:  $DC1_Ip" -ForegroundColor Gray
    Write-Host "  WS1:  $WS1_Ip" -ForegroundColor Gray
    Write-Host "  LIN1: $LIN1_Ip (static configured by script)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Host -> LIN1 SSH:" -ForegroundColor Cyan
    Write-Host "    ssh -o IdentitiesOnly=yes -i $SSHPrivateKey $LabInstallUser@$LIN1_Ip" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If you see the 'REMOTE HOST IDENTIFICATION HAS CHANGED' warning after a rebuild:" -ForegroundColor Cyan
    Write-Host "    ssh-keygen -R $LIN1_Ip" -ForegroundColor Yellow
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







