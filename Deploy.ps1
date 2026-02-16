# Deploy-SimpleLab.ps1 - Rebuildable 3-VM SimpleLab (AutomatedLab)
# Builds dc1 (AD/DNS/DHCP/CA), svr1 (Server 2019), ws1 (Windows 11) on Hyper-V
# Requires: AutomatedLab module, Hyper-V, ISOs in C:\LabSources\ISOs

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet('quick', 'full')]
    [string]$Mode = 'full',
    [switch]$NonInteractive,
    [switch]$ForceRebuild,
    [switch]$AutoFixSubnetConflict,
    [switch]$IncludeLIN1,
    [string]$GlobalLabConfig.Credentials.AdminPassword
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
$switchSubnetConflictHelperPath = Join-Path $ScriptDir 'Private\Test-LabVirtualSwitchSubnetConflict.ps1'
$templateHelperPath = Join-Path $ScriptDir 'Private\Get-ActiveTemplateConfig.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }
if (Test-Path $switchSubnetConflictHelperPath) { . $switchSubnetConflictHelperPath }
if (Test-Path $templateHelperPath) { . $templateHelperPath }

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RequestedMode = $Mode
$EffectiveMode = $Mode
if ($Mode -eq 'quick') {
    $EffectiveMode = 'full'
}

# ============================================================
# CONFIGURATION -- EDIT IF YOU WANT DIFFERENT IPs / NAMES
# ============================================================
# Config loaded from Lab-Config.ps1

# Deterministic lab install user (Windows is case-insensitive; Linux is not)
$GlobalLabConfig.Credentials.InstallUser = if ([string]::IsNullOrWhiteSpace($GlobalLabConfig.Credentials.LinuxUser)) { 'labadmin' } else { $GlobalLabConfig.Credentials.LinuxUser }
# Password resolution: -AdminPassword param → Lab-Config.ps1 → env var → error
# Lab-Config.ps1 (dot-sourced above) sets $GlobalLabConfig.Credentials.AdminPassword if our param was empty.
$GlobalLabConfig.Credentials.AdminPassword = Resolve-LabPassword -Password $GlobalLabConfig.Credentials.AdminPassword

$IsoPath        = "$GlobalLabConfig.Paths.LabSourcesRoot\ISOs"
$HostPublicKeyFileName = [System.IO.Path]::GetFileName((Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub))

# Backward-compatible defaults for Server1 topology if Lab-Config.ps1 is older.
if (-not (Get-Variable -Name Server1_Ip -ErrorAction SilentlyContinue)) { $GlobalLabConfig.IPPlan.SVR1 = '10.0.10.20' }
if (-not (Get-Variable -Name Server_Memory -ErrorAction SilentlyContinue)) { $GlobalLabConfig.VMSizing.Server.Memory = $GlobalLabConfig.VMSizing.DC.Memory }
if (-not (Get-Variable -Name Server_MinMemory -ErrorAction SilentlyContinue)) { $GlobalLabConfig.VMSizing.Server.MinMemory = $GlobalLabConfig.VMSizing.DC.MinMemory }
if (-not (Get-Variable -Name Server_MaxMemory -ErrorAction SilentlyContinue)) { $GlobalLabConfig.VMSizing.Server.MaxMemory = $GlobalLabConfig.VMSizing.DC.MaxMemory }
if (-not (Get-Variable -Name Server_Processors -ErrorAction SilentlyContinue)) { $GlobalLabConfig.VMSizing.Server.Processors = $GlobalLabConfig.VMSizing.DC.Processors }

# Legacy aliases (for backward compatibility)
if (-not (Get-Variable -Name WSUS_Memory -ErrorAction SilentlyContinue)) { $WSUS_Memory = $GlobalLabConfig.VMSizing.Server.Memory }
if (-not (Get-Variable -Name WSUS_MinMemory -ErrorAction SilentlyContinue)) { $WSUS_MinMemory = $GlobalLabConfig.VMSizing.Server.MinMemory }
if (-not (Get-Variable -Name WSUS_MaxMemory -ErrorAction SilentlyContinue)) { $WSUS_MaxMemory = $GlobalLabConfig.VMSizing.Server.MaxMemory }
if (-not (Get-Variable -Name WSUS_Processors -ErrorAction SilentlyContinue)) { $WSUS_Processors = $GlobalLabConfig.VMSizing.Server.Processors }

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
$logDir  = "$GlobalLabConfig.Paths.LabSourcesRoot\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = "$logDir\Deploy-SimpleLab_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"
Start-Transcript -Path $logFile -Append

try {
    if ($RequestedMode -eq 'quick') {
        Write-LabStatus -Status WARN -Message "Deploy.ps1 quick mode requested; this script performs full deployment. Falling back to full mode."
    }
    Write-LabStatus -Status INFO -Message "Deploy mode handoff: requested=$RequestedMode effective=$EffectiveMode"

    $deployStartTime = Get-Date
    Write-Host "`n[PRE-FLIGHT] Checking ISOs..." -ForegroundColor Cyan
    $missing = @()
    foreach ($iso in @($GlobalLabConfig.RequiredISOs)) {
        $p = Join-Path $IsoPath $iso
        if (Test-Path $p) { Write-LabStatus -Status OK -Message "$iso" }
        else { Write-Host "  [MISSING] $iso" -ForegroundColor Red; $missing += $iso }
    }
    if ($missing.Count -gt 0) {
        throw "Missing ISOs in ${IsoPath}: $($missing -join ', ')`nDownload from: https://www.microsoft.com/en-us/evalcenter/`nPlace files in: $IsoPath"
    }

    if (Get-Command -Name 'Test-LabVirtualSwitchSubnetConflict' -ErrorAction SilentlyContinue) {
        $subnetConflict = Test-LabVirtualSwitchSubnetConflict -SwitchName $GlobalLabConfig.Network.SwitchName -AddressSpace $GlobalLabConfig.Network.AddressSpace
        if ($subnetConflict.HasConflict) {
            $conflictSummary = @(
                $subnetConflict.ConflictingAdapters |
                    ForEach-Object { "$($_.InterfaceAlias) [$($_.IPAddress)]" }
            )
            Write-LabStatus -Status WARN -Message "Detected conflicting vEthernet subnet assignments for $($GlobalLabConfig.Network.AddressSpace): $($conflictSummary -join '; ')." -Indent 0

            $allowSubnetAutoFix = $AutoFixSubnetConflict

            if ($allowSubnetAutoFix) {
                $subnetConflict = Test-LabVirtualSwitchSubnetConflict -SwitchName $GlobalLabConfig.Network.SwitchName -AddressSpace $GlobalLabConfig.Network.AddressSpace -AutoFix
                if ($subnetConflict.AutoFixApplied) {
                    Write-LabStatus -Status WARN -Message "Auto-fixed $($subnetConflict.FixedAdapters.Count) vEthernet subnet conflict(s) for $GlobalLabConfig.Network.AddressSpace." -Indent 0
                }
            }

            if ($subnetConflict.HasConflict) {
                $reportConflicts = if ($subnetConflict.UnresolvedAdapters.Count -gt 0) {
                    $subnetConflict.UnresolvedAdapters
                }
                else {
                    $subnetConflict.ConflictingAdapters
                }

                $unresolvedSummary = @(
                    $reportConflicts |
                        ForEach-Object {
                            $hasError = $_.PSObject.Properties.Name -contains 'Error'
                            $errorSuffix = if (-not $hasError -or [string]::IsNullOrWhiteSpace([string]$_.Error)) { '' } else { " Error=$($_.Error)" }
                            "$($_.InterfaceAlias) [$($_.IPAddress)]$errorSuffix"
                        }
                )

                throw "Found conflicting Hyper-V vEthernet adapters in subnet '$GlobalLabConfig.Network.AddressSpace': $($unresolvedSummary -join '; '). Resolve the conflicts or change Lab-Config network settings before rerunning deploy. Use -AutoFixSubnetConflict to opt in to automatic remediation."
            }
        }
        else {
            Write-LabStatus -Status OK -Message "No conflicting vEthernet adapters found for subnet $GlobalLabConfig.Network.AddressSpace." -Indent 0
        }
    }
    else {
        Write-LabStatus -Status WARN -Message 'Subnet conflict preflight helper not found; skipping vEthernet subnet conflict check.' -Indent 0
    }

    # Remove existing lab if present
    if (Get-Lab -List | Where-Object { $_ -eq $GlobalLabConfig.Lab.Name }) {
        Write-Host "  Lab '$GlobalLabConfig.Lab.Name' already exists." -ForegroundColor Yellow
        $allowRebuild = $false
        if ($ForceRebuild -or $NonInteractive) {
            $allowRebuild = $true
        } else {
            $response = Read-Host "  Remove lab '$GlobalLabConfig.Lab.Name' and rebuild? Type 'yes' to confirm"
            if ($response -eq 'yes') { $allowRebuild = $true }
        }

        if ($allowRebuild) {
            Write-Host "  Removing existing lab..." -ForegroundColor Yellow
            $labMetaPath = Join-Path 'C:\ProgramData\AutomatedLab\Labs' $GlobalLabConfig.Lab.Name
            Remove-Lab -Name $GlobalLabConfig.Lab.Name -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            if (Get-Lab -List | Where-Object { $_ -eq $GlobalLabConfig.Lab.Name }) {
                Write-LabStatus -Status WARN -Message "AutomatedLab still reports '$GlobalLabConfig.Lab.Name' after removal attempt."
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
    if (-not (Test-Path (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519)) -or -not (Test-Path (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub))) {
        Write-Host "  Generating host SSH keypair..." -ForegroundColor Yellow
        Invoke-WindowsSshKeygen -PrivateKeyPath (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519) -Comment "lab-opencode"
        Write-Host "  SSH keypair ready at (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys)" -ForegroundColor Green
    } else {
        Write-Host "  SSH keypair found: (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519)" -ForegroundColor Green
    }

    # ============================================================
    # LAB DEFINITION
    # ============================================================
    Write-Host "`n[LAB] Defining lab '$GlobalLabConfig.Lab.Name' (creating VM specifications)..." -ForegroundColor Cyan

    # Increase AutomatedLab timeouts for resource-constrained hosts
    # Values MUST be TimeSpan objects -- passing plain integers is interpreted as
    # ticks (nanoseconds), which effectively sets the timeout to zero.
    Write-Host "  Applying AutomatedLab timeout overrides..." -ForegroundColor Yellow
    Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionRestartAfterDcpromo -Value $GlobalLabConfig.Timeouts.AutomatedLab.DcRestart
    Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionAdwsReady -Value $GlobalLabConfig.Timeouts.AutomatedLab.AdwsReady
    Set-PSFConfig -Module AutomatedLab -Name Timeout_StartLabMachine_Online -Value $GlobalLabConfig.Timeouts.AutomatedLab.StartVM
    Set-PSFConfig -Module AutomatedLab -Name Timeout_WaitLabMachine_Online -Value $GlobalLabConfig.Timeouts.AutomatedLab.WaitVM
    Write-Host "    DC restart: ${AL_Timeout_DcRestart}m, ADWS ready: ${AL_Timeout_AdwsReady}m, VM start/wait: ${AL_Timeout_StartVM}m" -ForegroundColor Gray

    New-LabDefinition -Name $GlobalLabConfig.Lab.Name -DefaultVirtualizationEngine HyperV -VmPath (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name)


    # Remove stale/conflicting VMs from previous failed runs.
    # This avoids "machine already exists" and broken-notes XML errors during Install-Lab.
    Write-Host "  Checking for stale lab VMs from prior runs..." -ForegroundColor Yellow
    foreach ($vmName in @($GlobalLabConfig.Lab.CoreVMNames)) {
        if (-not (Remove-HyperVVMStale -VMName $vmName -Context 'initial cleanup')) {
            throw "Failed to remove stale VM '$vmName'. Remove it manually in Hyper-V Manager, then re-run deploy."
        }
    }

    # Ensure vSwitch + NAT exist (idempotent)
    Write-Host "  Ensuring Hyper-V lab switch + NAT ($GlobalLabConfig.Network.SwitchName / $GlobalLabConfig.Network.AddressSpace)..." -ForegroundColor Yellow

    if (-not (Get-VMSwitch -Name $GlobalLabConfig.Network.SwitchName -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name $GlobalLabConfig.Network.SwitchName -SwitchType Internal | Out-Null
        Write-LabStatus -Status OK -Message "Created VMSwitch: $GlobalLabConfig.Network.SwitchName (Internal)" -Indent 2
    } else {
        Write-LabStatus -Status OK -Message "VMSwitch exists: $GlobalLabConfig.Network.SwitchName" -Indent 2
    }

    $ifAlias = "vEthernet ($GlobalLabConfig.Network.SwitchName)"
    $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.IPAddress -eq $GlobalLabConfig.Network.GatewayIp }
    if (-not $hasGw) {
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GlobalLabConfig.Network.GatewayIp -PrefixLength 24 | Out-Null
        Write-LabStatus -Status OK -Message "Set host gateway IP: $GlobalLabConfig.Network.GatewayIp on $ifAlias" -Indent 2
    } else {
        Write-LabStatus -Status OK -Message "Host gateway IP already set: $GlobalLabConfig.Network.GatewayIp" -Indent 2
    }

    $nat = Get-NetNat -Name $GlobalLabConfig.Network.NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        New-NetNat -Name $GlobalLabConfig.Network.NatName -InternalIPInterfaceAddressPrefix $GlobalLabConfig.Network.AddressSpace | Out-Null
        Write-LabStatus -Status OK -Message "Created NAT: $GlobalLabConfig.Network.NatName for $GlobalLabConfig.Network.AddressSpace" -Indent 2
    } elseif ($nat.InternalIPInterfaceAddressPrefix -ne $GlobalLabConfig.Network.AddressSpace) {
        Write-LabStatus -Status WARN -Message "NAT '$GlobalLabConfig.Network.NatName' exists with prefix '$($nat.InternalIPInterfaceAddressPrefix)'. Recreating..." -Indent 2
        Remove-NetNat -Name $GlobalLabConfig.Network.NatName -Confirm:$false | Out-Null
        New-NetNat -Name $GlobalLabConfig.Network.NatName -InternalIPInterfaceAddressPrefix $GlobalLabConfig.Network.AddressSpace | Out-Null
        Write-LabStatus -Status OK -Message "Recreated NAT: $GlobalLabConfig.Network.NatName for $GlobalLabConfig.Network.AddressSpace" -Indent 2
    } else {
        Write-LabStatus -Status OK -Message "NAT exists: $GlobalLabConfig.Network.NatName" -Indent 2
    }

    # Register network with AutomatedLab
    Add-LabVirtualNetworkDefinition -Name $GlobalLabConfig.Network.SwitchName -AddressSpace $GlobalLabConfig.Network.AddressSpace -HyperVProperties @{ SwitchType = 'Internal' }

    # Use the deterministic install credential everywhere
    Set-LabInstallationCredential -Username $GlobalLabConfig.Credentials.InstallUser -Password $GlobalLabConfig.Credentials.AdminPassword
    Add-LabDomainDefinition -Name $GlobalLabConfig.Lab.DomainName -AdminUser $GlobalLabConfig.Credentials.InstallUser -AdminPassword $GlobalLabConfig.Credentials.AdminPassword

    # ============================================================
    # MACHINE DEFINITIONS (template-aware or hardcoded fallback)
    # ============================================================
    $templateConfig = $null
    if (Get-Command -Name 'Get-ActiveTemplateConfig' -ErrorAction SilentlyContinue) {
        $templateConfig = Get-ActiveTemplateConfig -RepoRoot $ScriptDir
    }

    if ($templateConfig) {
        # ── Template-driven VM definitions ────────────────────────
        $templateVMNames = @($templateConfig | ForEach-Object { $_.Name })
        Write-Host "`n[LAB] Defining machines from active template ($($templateVMNames -join ' + '))..." -ForegroundColor Cyan

        # Role-to-AutomatedLab role tag mapping
        $roleTagMap = @{
            'DC'         = @('RootDC', 'CaRoot')
            'DSC'        = @('DSCPullServer')
            'IIS'        = @('WebServer')
            'DHCP'       = @('DHCPServer')
        }

        # Role-to-OS mapping
        $roleOSMap = @{
            'Client'     = 'Windows 11 Enterprise Evaluation'
            'Ubuntu'     = $null  # Handled separately via New-LinuxVM
        }
        $defaultOS = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'

        # Find the DC VM's IP for DNS references
        $dcVM = $templateConfig | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1
        $templateDnsIp = if ($dcVM) { $dcVM.Ip } else { $GlobalLabConfig.Network.DnsIp }

        foreach ($vmDef in $templateConfig) {
            # Skip Ubuntu VMs - they use New-LinuxVM path
            if ($vmDef.Role -eq 'Ubuntu') {
                Write-LabStatus -Status INFO -Message "Skipping '$($vmDef.Name)' from AutomatedLab definitions (Linux VM created separately)."
                continue
            }

            $memoryBytes = [int64]$vmDef.MemoryGB * 1GB
            $os = if ($roleOSMap.ContainsKey($vmDef.Role)) { $roleOSMap[$vmDef.Role] } else { $defaultOS }

            $machineParams = @{
                Name              = $vmDef.Name
                DomainName        = $GlobalLabConfig.Lab.DomainName
                Network           = $GlobalLabConfig.Network.SwitchName
                IpAddress         = $vmDef.Ip
                Gateway           = $GlobalLabConfig.Network.GatewayIp
                DnsServer1        = if ($vmDef.Role -eq 'DC') { $vmDef.Ip } else { $templateDnsIp }
                OperatingSystem   = $os
                Memory            = $memoryBytes
                MinMemory         = [int64]([math]::Floor($vmDef.MemoryGB / 2)) * 1GB
                MaxMemory         = [int64]([math]::Ceiling($vmDef.MemoryGB * 1.5)) * 1GB
                Processors        = $vmDef.Processors
            }

            # Add role tags if mapped
            if ($roleTagMap.ContainsKey($vmDef.Role)) {
                $machineParams['Roles'] = $roleTagMap[$vmDef.Role]
            }

            Add-LabMachineDefinition @machineParams
            Write-LabStatus -Status OK -Message "Defined VM: $($vmDef.Name) [Role=$($vmDef.Role), IP=$($vmDef.Ip), Mem=$($vmDef.MemoryGB)GB, CPUs=$($vmDef.Processors)]"
        }
    }
    else {
        # ── Hardcoded fallback (original 3-VM topology) ───────────
        if ($IncludeLIN1) {
            Write-Host "`n[LAB] Defining all machines (dc1 + svr1 + ws1 + LIN1)..." -ForegroundColor Cyan
        } else {
            Write-Host "`n[LAB] Defining Windows machines (dc1 + svr1 + ws1)..." -ForegroundColor Cyan
            Write-LabStatus -Status INFO -Message "Linux VM nodes are disabled for this run. Use -IncludeLIN1 to include Ubuntu."
        }

        Add-LabMachineDefinition -Name 'dc1' `
            -Roles RootDC, CaRoot `
            -DomainName $GlobalLabConfig.Lab.DomainName `
            -Network $GlobalLabConfig.Network.SwitchName `
            -IpAddress $GlobalLabConfig.IPPlan.DC1 -Gateway $GlobalLabConfig.Network.GatewayIp -DnsServer1 $GlobalLabConfig.IPPlan.DC1 `
            -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
            -Memory $GlobalLabConfig.VMSizing.DC.Memory -MinMemory $GlobalLabConfig.VMSizing.DC.MinMemory -MaxMemory $GlobalLabConfig.VMSizing.DC.MaxMemory `
            -Processors $GlobalLabConfig.VMSizing.DC.Processors

        Add-LabMachineDefinition -Name 'svr1' `
            -DomainName $GlobalLabConfig.Lab.DomainName `
            -Network $GlobalLabConfig.Network.SwitchName `
            -IpAddress $GlobalLabConfig.IPPlan.SVR1 -Gateway $GlobalLabConfig.Network.GatewayIp -DnsServer1 $GlobalLabConfig.Network.DnsIp `
            -OperatingSystem 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)' `
            -Memory $GlobalLabConfig.VMSizing.Server.Memory -MinMemory $GlobalLabConfig.VMSizing.Server.MinMemory -MaxMemory $GlobalLabConfig.VMSizing.Server.MaxMemory `
            -Processors $GlobalLabConfig.VMSizing.Server.Processors

        Add-LabMachineDefinition -Name 'ws1' `
            -DomainName $GlobalLabConfig.Lab.DomainName `
            -Network $GlobalLabConfig.Network.SwitchName `
            -IpAddress $GlobalLabConfig.IPPlan.WS1 -Gateway $GlobalLabConfig.Network.GatewayIp -DnsServer1 $GlobalLabConfig.Network.DnsIp `
            -OperatingSystem 'Windows 11 Enterprise Evaluation' `
            -Memory $GlobalLabConfig.VMSizing.Client.Memory -MinMemory $GlobalLabConfig.VMSizing.Client.MinMemory -MaxMemory $GlobalLabConfig.VMSizing.Client.MaxMemory `
            -Processors $GlobalLabConfig.VMSizing.Client.Processors
    }

    # NOTE: LIN1 is NOT added to AutomatedLab machine definitions
    # It will be created manually after Install-Lab to work around
    # AutomatedLab's lack of Ubuntu 24.04 support

    # ============================================================
    # INSTALL LAB (dc1 + svr1 + ws1 via AutomatedLab)
    # LIN1 will be created manually after this step if -IncludeLIN1 is set
    # ============================================================
    Write-Host "`n[INSTALL] Installing Windows machines (dc1 + svr1 + ws1)..." -ForegroundColor Cyan
    $installStart = Get-Date
    Write-Host "  Started at: $(Get-Date -Format 'HH:mm:ss'). This typically takes 15-45 minutes." -ForegroundColor Gray


    # Final guard: stale VMs can occasionally survive prior cleanup and cause
    # AutomatedLab errors like "machine already exists" or malformed LIN1 notes XML.
    Write-Host "  Final stale-VM check before Install-Lab..." -ForegroundColor Yellow
    foreach ($vmName in @($GlobalLabConfig.Lab.CoreVMNames)) {
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
        $wrmCheck = Test-NetConnection -ComputerName $GlobalLabConfig.IPPlan.DC1 -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($wrmCheck.TcpTestSucceeded) { $winrmReady = $true; break }
        Write-Host "    WinRM attempt $w/12..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
    if (-not $winrmReady) {
        throw "DC1 WinRM (port 5985) is unreachable. Cannot validate AD DS installation.`nTroubleshooting:`n  1. Check DC1 VM is running in Hyper-V Manager`n  2. Verify DC1 IP ($GlobalLabConfig.IPPlan.DC1) is pingable: Test-Connection $GlobalLabConfig.IPPlan.DC1`n  3. Check Windows Firewall on DC1 allows WinRM (port 5985)"
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

    if ($adStatus.NTDSRunning -and $adStatus.ADWorking -and $adStatus.CurrentDomain -eq $GlobalLabConfig.Lab.DomainName) {
        Write-LabStatus -Status OK -Message "DC1 is a domain controller for '$($adStatus.ForestName)'"
    } else {
        Write-LabStatus -Status WARN -Message "AD DS is NOT operational on DC1 after Install-Lab."
        Write-Host "    AD DS feature installed: $($adStatus.FeatureInstalled)" -ForegroundColor Yellow
        Write-Host "    NTDS service running:    $($adStatus.NTDSRunning)" -ForegroundColor Yellow
        Write-Host "    AD cmdlets working:      $($adStatus.ADWorking)" -ForegroundColor Yellow
        Write-Host "    Current domain:          '$($adStatus.CurrentDomain)' (expected: '$GlobalLabConfig.Lab.DomainName')" -ForegroundColor Yellow

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
        $netbiosDomain = ($GlobalLabConfig.Lab.DomainName -split '\.')[0].ToUpper()
        Write-Host "    Promoting DC1 to domain controller for '$GlobalLabConfig.Lab.DomainName' (NetBIOS: $netbiosDomain)..." -ForegroundColor Yellow

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
        } -ArgumentList $GlobalLabConfig.Lab.DomainName, $netbiosDomain, $GlobalLabConfig.Credentials.AdminPassword | Out-Null

        Write-LabStatus -Status OK -Message "Install-ADDSForest initiated. Waiting for DC1 to restart..." -Indent 2

        # Step 3: Wait for DC1 to go offline and come back
        # Wait for DC1 to go offline (restart initiated)
        $offlineDeadline = [datetime]::Now.AddSeconds(90)
        while ([datetime]::Now -lt $offlineDeadline) {
            $dc1Check = Test-NetConnection -ComputerName $GlobalLabConfig.IPPlan.DC1 -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if (-not $dc1Check.TcpTestSucceeded) { break }
            Start-Sleep -Seconds 5
        }

        $dc1Back = $false
        $restartDeadline = [datetime]::Now.AddMinutes(15)
        while ([datetime]::Now -lt $restartDeadline) {
            $rCheck = Test-NetConnection -ComputerName $GlobalLabConfig.IPPlan.DC1 -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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
            $warmupCheck = Test-NetConnection -ComputerName $GlobalLabConfig.IPPlan.DC1 -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
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
        if ($finalAd.ADWorking -and $finalAd.Domain -eq $GlobalLabConfig.Lab.DomainName) {
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
    $ifAlias = "vEthernet ($GlobalLabConfig.Network.SwitchName)"
    $hostIp = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -eq $GlobalLabConfig.Network.GatewayIp }
    if (-not $hostIp) {
        Write-LabStatus -Status WARN -Message "Host gateway IP $GlobalLabConfig.Network.GatewayIp missing on $ifAlias after Install-Lab. Re-applying..."
        Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GlobalLabConfig.Network.GatewayIp -PrefixLength 24 | Out-Null
        Write-LabStatus -Status OK -Message "Re-applied host gateway IP: $GlobalLabConfig.Network.GatewayIp"
    } else {
        Write-LabStatus -Status OK -Message "Host gateway IP intact: $GlobalLabConfig.Network.GatewayIp"
    }

    # 2. Verify NAT still exists
    $nat = Get-NetNat -Name $GlobalLabConfig.Network.NatName -ErrorAction SilentlyContinue
    if (-not $nat) {
        Write-LabStatus -Status WARN -Message "NAT '$GlobalLabConfig.Network.NatName' missing after Install-Lab. Recreating..."
        New-NetNat -Name $GlobalLabConfig.Network.NatName -InternalIPInterfaceAddressPrefix $GlobalLabConfig.Network.AddressSpace | Out-Null
        Write-LabStatus -Status OK -Message "Recreated NAT: $GlobalLabConfig.Network.NatName"
    } else {
        Write-LabStatus -Status OK -Message "NAT intact: $GlobalLabConfig.Network.NatName"
    }

    # 3. Ping DC1 to verify L3 connectivity
    $pingOk = Test-Connection -ComputerName $GlobalLabConfig.IPPlan.DC1 -Count 3 -Quiet -ErrorAction SilentlyContinue
    if (-not $pingOk) {
        throw "Cannot ping DC1 ($GlobalLabConfig.IPPlan.DC1) from host after Stage 1. Check vSwitch '$GlobalLabConfig.Network.SwitchName' and host adapter '$ifAlias'. Aborting before Stage 2."
    }
    Write-LabStatus -Status OK -Message "DC1 ($GlobalLabConfig.IPPlan.DC1) responds to ping"

    # 4. Verify WinRM connectivity (this is what AutomatedLab uses internally)
    $winrmOk = Test-NetConnection -ComputerName $GlobalLabConfig.IPPlan.DC1 -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if (-not $winrmOk.TcpTestSucceeded) {
        Write-LabStatus -Status WARN -Message "WinRM port 5985 not reachable on DC1 ($GlobalLabConfig.IPPlan.DC1). AD may still be starting."
        Write-Host "  Waiting 60s for WinRM to become available..." -ForegroundColor Yellow
        $retries = 6
        $winrmUp = $false
        for ($i = 1; $i -le $retries; $i++) {
            Start-Sleep -Seconds 10
            $check = Test-NetConnection -ComputerName $GlobalLabConfig.IPPlan.DC1 -Port 5985 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($check.TcpTestSucceeded) { $winrmUp = $true; break }
            Write-Host "    Retry $i/$retries..." -ForegroundColor Gray
        }
        if (-not $winrmUp) {
            throw "WinRM (port 5985) on DC1 ($GlobalLabConfig.IPPlan.DC1) is unreachable after 60s. Cannot proceed to Stage 2."
        }
    }
    Write-LabStatus -Status OK -Message "WinRM reachable on DC1 ($GlobalLabConfig.IPPlan.DC1):5985"
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
    } -ArgumentList $GlobalLabConfig.DHCP.ScopeId, $GlobalLabConfig.DHCP.Start, $GlobalLabConfig.DHCP.End, $GlobalLabConfig.DHCP.Mask, $GlobalLabConfig.Network.GatewayIp, $GlobalLabConfig.Network.DnsIp, $GlobalLabConfig.Lab.DomainName | Out-Null

    Write-LabStatus -Status OK -Message "DHCP scope configured: $GlobalLabConfig.DHCP.ScopeId ($GlobalLabConfig.DHCP.Start - $GlobalLabConfig.DHCP.End)"

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
                $lin1PwHash = Get-Sha512PasswordHash -Password $GlobalLabConfig.Credentials.AdminPassword

                # Read SSH public key if available
                $lin1SshPubKey = ''
                if (Test-Path (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub)) {
                    $lin1SshPubKey = (Get-Content (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub) -Raw).Trim()
                }

                # Create CIDATA VHDX seed disk with autoinstall user-data
                $cidataPath = Join-Path (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name) 'LIN1-cidata.vhdx'
                Write-Host "  Creating CIDATA seed disk with autoinstall config..." -ForegroundColor Gray
                New-CidataVhdx -OutputPath $cidataPath `
                    -Hostname 'LIN1' `
                    -Username $GlobalLabConfig.Credentials.InstallUser `
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
                    Remove-Item (Join-Path (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name) 'LIN1.vhdx') -Force -ErrorAction SilentlyContinue
                    Remove-Item (Join-Path (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name) 'LIN1-cidata.vhdx') -Force -ErrorAction SilentlyContinue

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

$lin1WaitMinutes = $GlobalLabConfig.Timeouts.Linux.LIN1WaitMinutes
            Write-Host "`n[LIN1] Waiting for unattended Ubuntu install + SSH (up to $lin1WaitMinutes min)..." -ForegroundColor Cyan
            $lin1WaitResult = Wait-LinuxVMReady -VMName 'LIN1' -WaitMinutes $lin1WaitMinutes -DhcpServer 'DC1' -ScopeId $GlobalLabConfig.DHCP.ScopeId
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
        param($GlobalLabConfig.Paths.SharePath, $GlobalLabConfig.Paths.ShareName, $GlobalLabConfig.Paths.GitRepoPath, $GlobalLabConfig.Lab.DomainName)

        New-Item -Path $GlobalLabConfig.Paths.SharePath -ItemType Directory -Force | Out-Null
        New-Item -Path $GlobalLabConfig.Paths.GitRepoPath -ItemType Directory -Force | Out-Null
        New-Item -Path "$GlobalLabConfig.Paths.SharePath\Transfer" -ItemType Directory -Force | Out-Null
        New-Item -Path "$GlobalLabConfig.Paths.SharePath\Tools" -ItemType Directory -Force | Out-Null

        $netbios = ($GlobalLabConfig.Lab.DomainName -split '\.')[0].ToUpper()
        try {
            New-ADGroup -Name 'LabShareUsers' -GroupScope DomainLocal -Path "CN=Users,DC=$($GlobalLabConfig.Lab.DomainName -replace '\.',',DC=')" -ErrorAction Stop | Out-Null
        } catch {
            Write-Verbose "LabShareUsers group create skipped: $($_.Exception.Message)"
        }

        try {
            Add-ADGroupMember -Identity 'LabShareUsers' -Members 'Domain Users' -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "LabShareUsers add Domain Users skipped: $($_.Exception.Message)"
        }

        try {
            if (-not (Get-SmbShare -Name $GlobalLabConfig.Paths.ShareName -ErrorAction SilentlyContinue)) {
                New-SmbShare -Name $GlobalLabConfig.Paths.ShareName -Path $GlobalLabConfig.Paths.SharePath `
                    -FullAccess "$netbios\LabShareUsers", "$netbios\Domain Admins" `
                    -Description 'OpenCode Lab Shared Storage' | Out-Null
            }
        } catch {
            Write-Verbose "SMB share create/check skipped: $($_.Exception.Message)"
        }

        $acl = Get-Acl $GlobalLabConfig.Paths.SharePath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$netbios\LabShareUsers", 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl $GlobalLabConfig.Paths.SharePath $acl

        "Share ready"
    } -ArgumentList $GlobalLabConfig.Paths.SharePath, $GlobalLabConfig.Paths.ShareName, $GlobalLabConfig.Paths.GitRepoPath, $GlobalLabConfig.Lab.DomainName | Out-Null

    # Add domain members to share group (after join)
    Invoke-LabCommand -ComputerName 'DC1' -ActivityName 'Add-Clients-To-ShareGroup' -ScriptBlock {
        try {
            Add-ADGroupMember -Identity 'LabShareUsers' -Members 'ws1$' -ErrorAction Stop | Out-Null
            Add-ADGroupMember -Identity 'LabShareUsers' -Members 'svr1$' -ErrorAction SilentlyContinue | Out-Null
        } catch {
            Write-Verbose "LabShareUsers membership update skipped: $($_.Exception.Message)"
        }
    } | Out-Null

    $gitInstallerScriptBlock = {
        param(
            [string]$LocalInstallerPath,
            [string]$GitDownloadUrl,
            [string]$ExpectedSha256
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

                # Validate download integrity
                if ($ExpectedSha256) {
                    $actualHash = (Get-FileHash -Path $gitInstaller -Algorithm SHA256).Hash
                    if ($actualHash -ne $ExpectedSha256) {
                        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
                        $result.Message = "Git installer checksum mismatch (expected $ExpectedSha256, got $actualHash)"
                        return $result
                    }
                }

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
        $dc1GitResults = @(Invoke-LabCommand -ComputerName 'DC1' -PassThru -ActivityName 'Install-Git-DC1' -ScriptBlock $gitInstallerScriptBlock -ArgumentList 'C:\LabSources\SoftwarePackages\Git\Git-2.47.1.2-64-bit.exe', 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe', '0229E3ACB535D0DC5F0D4A7E33CD36E3E3BA5B67A44B507B4D5E6A63B0B8BBDE')

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
        Copy-LabFileItem -Path (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub) -ComputerName 'DC1' -DestinationFolderPath 'C:\ProgramData\ssh'

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
    # svr1: keep as fresh Windows Server 2019 member server
    # ============================================================
    Write-Host "`n[POST] svr1 baseline..." -ForegroundColor Cyan
    Write-LabStatus -Status OK -Message "svr1 left as a clean Windows Server 2019 VM (no WSUS role installed)."
    Write-LabStatus -Status INFO -Message "Install additional roles/features on svr1 manually when ready."

    # ============================================================
    # ws1: client basics (RSAT + drive map)
    # ============================================================
    Write-Host "`n[POST] Configuring ws1..." -ForegroundColor Cyan

    # RSAT install: domain GP may redirect Windows Update through DC1 (no WSUS),
    # causing "Access is denied" COMException. Temporarily bypass the WSUS policy.
    try {
        Invoke-LabCommand -ComputerName 'ws1' -ActivityName 'Install-RSAT-ws1' -ScriptBlock {
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
        Write-LabStatus -Status OK -Message "RSAT capabilities installed on ws1"
    }
    catch {
        Write-LabStatus -Status WARN -Message "RSAT installation failed: $($_.Exception.Message)"
        Write-LabStatus -Status WARN -Message "ws1 will work without RSAT. Install manually later if needed."
    }

    Invoke-LabCommand -ComputerName 'ws1' -ActivityName 'Map-LabShare' -ScriptBlock {
        param($GlobalLabConfig.Paths.ShareName)
        net use L: "\\DC1\$GlobalLabConfig.Paths.ShareName" /persistent:yes 2>$null
    } -ArgumentList $GlobalLabConfig.Paths.ShareName | Out-Null

    # ws1: WinRM HTTPS + ICMP
    Invoke-LabCommand -ComputerName 'ws1' -ActivityName 'Configure-WinRM-HTTPS-ws1' -ScriptBlock {
        $fqdn = "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
        $cert = New-SelfSignedCertificate -DnsName $fqdn, $env:COMPUTERNAME -CertStoreLocation 'Cert:\LocalMachine\My' -NotAfter (Get-Date).AddYears(5)

        Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' } |
            ForEach-Object { Remove-Item $_.PSPath -Recurse -Force }

        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

        New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName 'ICMPv4 Allow' -Protocol ICMPv4 -IcmpType 8 -Action Allow -Direction Inbound -ErrorAction SilentlyContinue | Out-Null
    } | Out-Null

    # ws1: Git (winget preferred, with offline/web fallback)
    try {
        $ws1GitResults = @(Invoke-LabCommand -ComputerName 'ws1' -PassThru -ActivityName 'Install-Git-ws1' -ScriptBlock $gitInstallerScriptBlock -ArgumentList 'C:\LabSources\SoftwarePackages\Git\Git-2.47.1.2-64-bit.exe', 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe', '0229E3ACB535D0DC5F0D4A7E33CD36E3E3BA5B67A44B507B4D5E6A63B0B8BBDE')

        $ws1GitResult = @($ws1GitResults | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'Installed' } | Select-Object -Last 1)

        if ($ws1GitResult.Count -gt 0 -and $ws1GitResult[0].Installed) {
            Write-LabStatus -Status OK -Message "$($ws1GitResult[0].Message)"
        } elseif ($ws1GitResult.Count -gt 0) {
            $msg = if ($ws1GitResult[0].Message) { $ws1GitResult[0].Message } else { 'Unknown Git install failure on ws1.' }
            Write-LabStatus -Status WARN -Message "$msg"
            Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on ws1."
        } else {
            Write-LabStatus -Status WARN -Message "Git installation step on ws1 returned no structured result."
            Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on ws1."
        }
    } catch {
        Write-LabStatus -Status WARN -Message "Git installation step on ws1 failed: $($_.Exception.Message)"
        Write-LabStatus -Status WARN -Message "Continuing deployment without guaranteed Git on ws1."
    }


    # ============================================================
    # LIN1: deterministic user, SSH keys, static IP, SMB mount, dev tools
    # ============================================================
    if ($IncludeLIN1 -and $lin1Ready) {
    Write-Host "`n[POST] Configuring LIN1 (Ubuntu dev host)..." -ForegroundColor Cyan

    $netbios = ($GlobalLabConfig.Lab.DomainName -split '\.')[0].ToUpper()
    $linUser = $GlobalLabConfig.Credentials.InstallUser
    $linHome = "/home/$linUser"


    $escapedPassword = $GlobalLabConfig.Credentials.AdminPassword -replace "'", "'\\''"

    $lin1ScriptContent = Get-Content (Join-Path $ScriptDir 'Scripts\Configure-LIN1.sh') -Raw
    Copy-LabFileItem -Path (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519.pub) -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

    $lin1Vars = @{
        LIN_USER = $linUser
        LIN_HOME = $linHome
        DOMAIN = $GlobalLabConfig.Lab.DomainName
        NETBIOS = $netbios
        SHARE = $GlobalLabConfig.Paths.ShareName
        PASS = $escapedPassword
        GATEWAY = $GlobalLabConfig.Network.GatewayIp
        DNS = $GlobalLabConfig.Network.DnsIp
        STATIC_IP = $GlobalLabConfig.IPPlan.LIN1
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
    Write-Host "  DC1:  $GlobalLabConfig.IPPlan.DC1" -ForegroundColor Gray
    Write-Host "  svr1:  $GlobalLabConfig.IPPlan.SVR1" -ForegroundColor Gray
    Write-Host "  ws1:   $GlobalLabConfig.IPPlan.WS1" -ForegroundColor Gray
    if ($IncludeLIN1 -and $lin1Ready) {
        Write-Host "  LIN1: $GlobalLabConfig.IPPlan.LIN1 (static configured by script)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Host -> LIN1 SSH:" -ForegroundColor Cyan
        Write-Host "    ssh -o IdentitiesOnly=yes -i (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519) $GlobalLabConfig.Credentials.InstallUser@$GlobalLabConfig.IPPlan.LIN1" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  If you see the 'REMOTE HOST IDENTIFICATION HAS CHANGED' warning after a rebuild:" -ForegroundColor Cyan
        Write-Host "    ssh-keygen -R $GlobalLabConfig.IPPlan.LIN1" -ForegroundColor Yellow
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
