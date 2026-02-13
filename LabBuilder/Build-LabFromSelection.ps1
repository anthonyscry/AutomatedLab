function Build-LabFromSelection {
    <#
    .SYNOPSIS
        Builds a Hyper-V lab from the selected role tags using AutomatedLab.
    .DESCRIPTION
        Maps selected role tags to machine definitions, creates the lab,
        runs post-install scripts per role, and writes a JSON summary.
        Idempotent: cleans existing lab before rebuilding.
    .PARAMETER SelectedRoles
        Array of role tags to build (e.g., @('DC','DSC','IIS')).
        DC is always required and should always be included.
    .PARAMETER ConfigPath
        Path to LabDefaults.psd1. Defaults to Config\LabDefaults.psd1 in script directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SelectedRoles,

        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    $buildStartTime = [datetime]::Now

    # ================================================================
    # Phase 1: Load Configuration
    # ================================================================
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot 'Config\LabDefaults.psd1'
    }
    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $Config = Import-PowerShellDataFile -Path $ConfigPath
    # Add SelectedRoles so PostInstall scripts can check membership
    $Config.SelectedRoles = $SelectedRoles

    # ================================================================
    # Phase 2: Resolve Credentials (no plaintext in code)
    # ================================================================
    $envPassword = [System.Environment]::GetEnvironmentVariable($Config.CredentialEnvVar)
    if ([string]::IsNullOrWhiteSpace($envPassword)) {
        Write-Host "  Environment variable '$($Config.CredentialEnvVar)' not set." -ForegroundColor Yellow
        $securePass = Read-Host -Prompt '  Enter lab admin password' -AsSecureString
    }
    else {
        $securePass = ConvertTo-SecureString -String $envPassword -AsPlainText -Force
    }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    # ================================================================
    # Phase 3: Start Logging
    # ================================================================
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logDir = Join-Path $PSScriptRoot 'Logs'
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    $transcriptPath = Join-Path $logDir "LabBuild-$timestamp.log"
    $summaryPath    = Join-Path $logDir "LabBuild-$timestamp.summary.json"
    Start-Transcript -Path $transcriptPath -Append

    $timings   = @{}
    $buildStart = Get-Date
    $timingData = @{}

    Write-Host ''
    Write-Host ('  ' + ('=' * 55)) -ForegroundColor Cyan
    Write-Host '  LabBuilder - Starting Build' -ForegroundColor Cyan
    Write-Host ('  ' + ('=' * 55)) -ForegroundColor Cyan
    Write-Host "  Roles: $($SelectedRoles -join ', ')" -ForegroundColor White
    Write-Host "  Time:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ''

    try {
        # ============================================================
        # Phase 4: Pre-Flight Checks
        # ============================================================
        Write-Host '  [Phase 4] Pre-flight checks...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        # 4a. AutomatedLab module available?
        if (-not (Get-Module -ListAvailable -Name AutomatedLab)) {
            throw "AutomatedLab module not installed. Run: Install-Module AutomatedLab -Force -Scope CurrentUser"
        }

        # 4b. ISOs exist?
        $isoDir = Join-Path $Config.LabSourcesRoot 'ISOs'
        $missingISOs = @()
        foreach ($iso in $Config.RequiredISOs) {
            $isoPath = Join-Path $isoDir $iso
            if (-not (Test-Path $isoPath)) { $missingISOs += $iso }
        }
        if ($missingISOs.Count -gt 0) {
            throw "Missing ISOs in ${isoDir}: $($missingISOs -join ', ')"
        }

        Write-Host '    [OK] Pre-flight checks passed.' -ForegroundColor Green
        $timings['PreFlight'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 5: Import AutomatedLab Module
        # ============================================================
        Write-Host '  [Phase 5] Importing AutomatedLab module...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        Import-Module AutomatedLab -ErrorAction Stop
        Write-Host '    [OK] AutomatedLab imported.' -ForegroundColor Green

        $timings['ImportModule'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 6: Clean Existing Lab (idempotent)
        # ============================================================
        Write-Host '  [Phase 6] Cleaning existing lab...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        # Dot-source Lab-Common.ps1 from parent for Remove-HyperVVMStale
        $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
        if (Test-Path $labCommonPath) {
            . $labCommonPath
        }

        # Remove existing lab definition if present
        $existingLabs = Get-Lab -List -ErrorAction SilentlyContinue
        if ($existingLabs -and ($Config.LabName -in $existingLabs)) {
            Write-Host "    Removing existing lab '$($Config.LabName)'..." -ForegroundColor DarkYellow
            Remove-Lab -Name $Config.LabName -Confirm:$false -ErrorAction SilentlyContinue
            $labMetaPath = Join-Path 'C:\ProgramData\AutomatedLab\Labs' $Config.LabName
            if (Test-Path $labMetaPath) {
                Remove-Item -Path $labMetaPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Remove stale VMs for selected roles
        foreach ($tag in $SelectedRoles) {
            $vmName = $Config.VMNames[$tag]
            if (Get-Command Remove-HyperVVMStale -ErrorAction SilentlyContinue) {
                Remove-HyperVVMStale -VMName $vmName -Context 'LabBuilder cleanup' | Out-Null
            }
            else {
                # Fallback if Lab-Common.ps1 not found
                $vm = Hyper-V\Get-VM -Name $vmName -ErrorAction SilentlyContinue
                if ($vm) {
                    if ($vm.State -ne 'Off') {
                        Hyper-V\Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                    }
                    Hyper-V\Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Write-Host '    [OK] Cleanup complete.' -ForegroundColor Green
        $timings['CleanExisting'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 7: Load Role Scripts
        # ============================================================
        Write-Host '  [Phase 7] Loading role scripts...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        $roleScriptMap = @{
            DC         = @{ File = 'DC.ps1';             Function = 'Get-LabRole_DC' }
            DSC        = @{ File = 'DSCPullServer.ps1';  Function = 'Get-LabRole_DSC' }
            IIS        = @{ File = 'IIS.ps1';            Function = 'Get-LabRole_IIS' }
            SQL        = @{ File = 'SQL.ps1';            Function = 'Get-LabRole_SQL' }
            WSUS       = @{ File = 'WSUS.ps1';           Function = 'Get-LabRole_WSUS' }
            FileServer = @{ File = 'FileServer.ps1';     Function = 'Get-LabRole_FileServer' }
            Jumpbox    = @{ File = 'Jumpbox.ps1';        Function = 'Get-LabRole_Jumpbox' }
            Client     = @{ File = 'Client.ps1';         Function = 'Get-LabRole_Client' }
            Ubuntu     = @{ File = 'Ubuntu.ps1';         Function = 'Get-LabRole_Ubuntu' }
        }

        $roleDefs = @()
        foreach ($tag in $SelectedRoles) {
            $entry = $roleScriptMap[$tag]
            if (-not $entry) {
                throw "Unknown role tag: $tag"
            }
            $scriptPath = Join-Path $PSScriptRoot "Roles\$($entry.File)"
            if (-not (Test-Path $scriptPath)) {
                throw "Role script not found: $scriptPath"
            }
            . $scriptPath
            $fn = Get-Command $entry.Function -ErrorAction Stop
            $roleDef = & $fn -Config $Config
            $roleDefs += $roleDef
            Write-Host "    [OK] Loaded: $($entry.File) -> $($roleDef.VMName)" -ForegroundColor Green
        }

        $timings['LoadRoles'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 8: Create Lab Definition
        # ============================================================
        Write-Host '  [Phase 8] Creating lab definition...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        New-LabDefinition -Name $Config.LabName -DefaultVirtualizationEngine HyperV -VmPath $Config.LabPath

        # Set AutomatedLab timeout overrides
        Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionRestartAfterDcpromo -Value $Config.Timeouts.DcRestart
        Set-PSFConfig -Module AutomatedLab -Name Timeout_DcPromotionAdwsReady          -Value $Config.Timeouts.AdwsReady
        Set-PSFConfig -Module AutomatedLab -Name Timeout_StartLabMachine_Online         -Value $Config.Timeouts.StartVM
        Set-PSFConfig -Module AutomatedLab -Name Timeout_WaitLabMachine_Online          -Value $Config.Timeouts.WaitVM

        # Network setup
        $net = $Config.Network

        # Ensure vSwitch exists
        if (-not (Get-VMSwitch -Name $net.SwitchName -ErrorAction SilentlyContinue)) {
            New-VMSwitch -Name $net.SwitchName -SwitchType Internal | Out-Null
            Write-Host "    [OK] Created vSwitch: $($net.SwitchName)" -ForegroundColor Green
        }

        # Ensure host gateway IP
        $ifAlias = "vEthernet ($($net.SwitchName))"
        $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -eq $net.Gateway }
        if (-not $hasGw) {
            Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $net.Gateway -PrefixLength 24 | Out-Null
            Write-Host "    [OK] Set host gateway IP: $($net.Gateway)" -ForegroundColor Green
        }

        # Ensure NAT
        $nat = Get-NetNat -Name $net.NatName -ErrorAction SilentlyContinue
        if (-not $nat) {
            New-NetNat -Name $net.NatName -InternalIPInterfaceAddressPrefix $net.AddressSpace | Out-Null
            Write-Host "    [OK] Created NAT: $($net.NatName)" -ForegroundColor Green
        }

        # Register network with AutomatedLab
        Add-LabVirtualNetworkDefinition -Name $net.SwitchName -AddressSpace $net.AddressSpace `
            -HyperVProperties @{ SwitchType = 'Internal' }

        # Credentials + Domain
        Set-LabInstallationCredential -Username $Config.CredentialUser -Password $plainPass
        Add-LabDomainDefinition -Name $Config.DomainName -AdminUser $Config.CredentialUser -AdminPassword $plainPass

        Write-Host '    [OK] Lab definition created.' -ForegroundColor Green
        $timings['LabDefinition'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 9: Add Machine Definitions
        # ============================================================
        Write-Host '  [Phase 9] Adding machine definitions...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        foreach ($rd in $roleDefs) {
            if ($rd.SkipInstallLab) {
                Write-Host "    Skipping (Linux): $($rd.VMName.PadRight(12)) $($rd.IP.PadRight(16)) [$($rd.Tag)]" -ForegroundColor DarkCyan
                continue
            }

            $machineParams = @{
                Name            = $rd.VMName
                DomainName      = $rd.DomainName
                Network         = $rd.Network
                IpAddress       = $rd.IP
                Gateway         = $rd.Gateway
                DnsServer1      = $rd.DnsServer1
                OperatingSystem = $rd.OS
                Memory          = $rd.Memory
                MinMemory       = $rd.MinMemory
                MaxMemory       = $rd.MaxMemory
                Processors      = $rd.Processors
            }

            # Add AutomatedLab built-in roles if any (DC has RootDC, CaRoot)
            if ($rd.Roles -and $rd.Roles.Count -gt 0) {
                $machineParams['Roles'] = $rd.Roles
            }

            Write-Host "    Adding: $($rd.VMName.PadRight(12)) $($rd.IP.PadRight(16)) [$($rd.Tag)]" -ForegroundColor Cyan
            Add-LabMachineDefinition @machineParams
        }

        $timings['MachineDefinitions'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 10-pre: Launch Linux VM Creation in Background
        # ============================================================
        $linuxJobs = @()
        $linuxRoles = @($roleDefs | Where-Object { $_.IsLinux -eq $true })
        if ($linuxRoles.Count -gt 0) {
            Write-Host '' -ForegroundColor White
            Write-Host '  [Phase 10-pre] Launching Linux VM creation in background...' -ForegroundColor Yellow

            foreach ($rd in $linuxRoles) {
                $createBlock = $rd.CreateVM
                if (-not $createBlock) { continue }

                Write-Host "    Starting background job for $($rd.VMName)..." -ForegroundColor Gray
                $jobConfig = $Config
                $jobLabCommon = Join-Path $PSScriptRoot '..\Lab-Common.ps1'
                $jobLabConfig = Join-Path $PSScriptRoot '..\Lab-Config.ps1'

                $job = Start-Job -ScriptBlock {
                    param($ConfigData, $CommonPath, $ConfigPath, $CreateScript)

                    if (Test-Path $ConfigPath) { . $ConfigPath }
                    if (Test-Path $CommonPath) { . $CommonPath }

                    $block = [scriptblock]::Create($CreateScript)
                    & $block $ConfigData
                } -ArgumentList $jobConfig, $jobLabCommon, $jobLabConfig, $createBlock.ToString()

                $linuxJobs += @{
                    Job = $job
                    VMName = $rd.VMName
                    Tag = $rd.Tag
                }
            }
        }

        # ============================================================
        # Phase 10: Install Lab
        # ============================================================
        Write-Host '' -ForegroundColor White
        Write-Host '  [Phase 10] Installing lab (this may take 15-45 minutes)...' -ForegroundColor Yellow
        Write-Host '    VMs being deployed:' -ForegroundColor White
        foreach ($rd in $roleDefs) {
            Write-Host "      $($rd.VMName.PadRight(12)) $($rd.IP.PadRight(16)) $($rd.Tag)" -ForegroundColor Gray
        }
        Write-Host ''

        $phaseStart = Get-Date
        Install-Lab -ErrorAction Stop
        $timings['InstallLab'] = (Get-Date) - $phaseStart

        Write-Host '    [OK] Lab installation complete.' -ForegroundColor Green

        # ============================================================
        # Phase 10.5: Wait for Linux VM Creation Jobs
        # ============================================================
        if ($linuxJobs.Count -gt 0) {
            Write-Host '' -ForegroundColor White
            Write-Host '  [Phase 10.5] Waiting for Linux VM creation to complete...' -ForegroundColor Yellow
            $phaseStart = Get-Date

            foreach ($lj in $linuxJobs) {
                Write-Host "    Waiting for $($lj.VMName)..." -ForegroundColor Gray
                $result = Receive-Job -Job $lj.Job -Wait -ErrorAction SilentlyContinue 2>&1
                if ($lj.Job.State -eq 'Failed') {
                    Write-Host "    [WARN] $($lj.VMName) creation failed:" -ForegroundColor Yellow
                    $result | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
                    Write-Host '    You can create it manually later with Add-LIN1.ps1' -ForegroundColor Yellow
                }
                else {
                    Write-Host "    [OK] $($lj.VMName) background creation completed" -ForegroundColor Green
                }
                Remove-Job -Job $lj.Job -Force -ErrorAction SilentlyContinue
            }

            $timings['LinuxVMs'] = (Get-Date) - $phaseStart
        }

        # ============================================================
        # Phase 11: Run Post-Install Scripts (DC first, then others)
        # ============================================================
        Write-Host '' -ForegroundColor White
        Write-Host '  [Phase 11] Running post-install scripts...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        # DC must run first (AD services needed by other post-installs)
        $dcRole = $roleDefs | Where-Object { $_.Tag -eq 'DC' }
        if ($dcRole -and $dcRole.PostInstall) {
            Write-Host "    Running post-install: $($dcRole.VMName)..." -ForegroundColor Yellow
            & $dcRole.PostInstall $Config
        }

        # Then all other roles (not DC)
        foreach ($rd in $roleDefs) {
            if ($rd.Tag -eq 'DC') { continue }
            if ($rd.IsLinux) { continue }
            if ($rd.PostInstall) {
                Write-Host "    Running post-install: $($rd.VMName)..." -ForegroundColor Yellow
                try {
                    & $rd.PostInstall $Config
                }
                catch {
                    Write-Warning "Post-install for $($rd.VMName) failed: $($_.Exception.Message)"
                    Write-Host '    Continuing with remaining post-installs...' -ForegroundColor Yellow
                }
            }
        }

        # Linux post-installs run after all Windows post-installs
        foreach ($rd in $roleDefs) {
            if (-not $rd.IsLinux) { continue }
            if ($rd.PostInstall) {
                Write-Host "    Running post-install: $($rd.VMName) [Linux]..." -ForegroundColor Yellow
                try {
                    & $rd.PostInstall $Config
                }
                catch {
                    Write-Warning "Post-install for $($rd.VMName) failed: $($_.Exception.Message)"
                    Write-Host '    Continuing with remaining post-installs...' -ForegroundColor Yellow
                }
            }
        }

        $timings['PostInstall'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 12: Create LabReady Checkpoint
        # ============================================================
        Write-Host '' -ForegroundColor White
        Write-Host '  [Phase 12] Creating LabReady checkpoint...' -ForegroundColor Yellow
        $phaseStart = Get-Date

        $labVMs = Get-LabVM -ErrorAction SilentlyContinue
        foreach ($vm in $labVMs) {
            Checkpoint-LabVM -VMName $vm.Name -SnapshotName 'LabReady' -ErrorAction SilentlyContinue
        }

        # Checkpoint Linux VMs (not managed by AutomatedLab)
        foreach ($rd in $linuxRoles) {
            try {
                Hyper-V\Checkpoint-VM -Name $rd.VMName -SnapshotName 'LabReady' -ErrorAction SilentlyContinue
                Write-Host "    [OK] LabReady checkpoint: $($rd.VMName)" -ForegroundColor Green
            }
            catch {
                Write-Warning "Checkpoint for $($rd.VMName) failed: $($_.Exception.Message)"
            }
        }

        Write-Host '    [OK] LabReady checkpoint created.' -ForegroundColor Green
        $timings['Checkpoint'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 13: Write Summary
        # ============================================================
        $buildEnd = Get-Date
        $totalDuration = $buildEnd - $buildStart

        # Build machine plan
        $machinePlan = @()
        foreach ($rd in $roleDefs) {
            $machinePlan += @{
                VMName  = $rd.VMName
                IP      = $rd.IP
                Tag     = $rd.Tag
                Role    = $rd.Tag
                OS      = $rd.OS
                IsLinux = [bool]$rd.IsLinux
            }
        }

        # Build timing data
        foreach ($key in $timings.Keys) {
            $timingData[$key] = @{
                Seconds = [math]::Round($timings[$key].TotalSeconds, 1)
                Display = $timings[$key].ToString('hh\:mm\:ss')
            }
        }

        $summary = @{
            LabName       = $Config.LabName
            DomainName    = $Config.DomainName
            BuildTimestamp = $buildStart.ToString('o')
            TotalDuration = @{
                Seconds = [math]::Round($totalDuration.TotalSeconds, 1)
                Display = $totalDuration.ToString('hh\:mm\:ss')
            }
            SelectedRoles = $SelectedRoles
            Machines      = $machinePlan
            Timings       = $timingData
            TranscriptLog = $transcriptPath
            Success       = $true
        }

        $summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8

        # Print summary to console
        Write-Host ''
        Write-Host ('  ' + ('=' * 55)) -ForegroundColor Green
        Write-Host '  LabBuilder - Build Complete' -ForegroundColor Green
        Write-Host ('  ' + ('=' * 55)) -ForegroundColor Green
        Write-Host ''
        Write-Host "  Lab:      $($Config.LabName)" -ForegroundColor Cyan
        Write-Host "  Domain:   $($Config.DomainName)" -ForegroundColor Cyan
        Write-Host "  Duration: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  VM Name       IP Address       Role' -ForegroundColor White
        Write-Host '  -------       ----------       ----' -ForegroundColor Gray
        foreach ($m in $machinePlan) {
            $osTag = if ($m.IsLinux) { '[LIN]' } else { '[WIN]' }
            $osColor = if ($m.IsLinux) { 'DarkCyan' } else { 'White' }
            Write-Host '  ' -NoNewline
            Write-Host "$osTag " -NoNewline -ForegroundColor $osColor
            Write-Host "$($m.VMName.PadRight(12)) $($m.IP.PadRight(17)) $($m.Role)" -ForegroundColor White
        }
        Write-Host ''
        Write-Host "  Transcript: $transcriptPath" -ForegroundColor Gray
        Write-Host "  Summary:    $summaryPath" -ForegroundColor Gray
        Write-Host ''

        # -- Phase 14: Deployment Report --
        Write-Host "`n  [Phase 14] Generating deployment report..." -ForegroundColor Yellow
        try {
            $reportMachines = @()
            foreach ($m in $machinePlan) {
                $vmObj = Hyper-V\Get-VM -Name $m.VMName -ErrorAction SilentlyContinue
                $vmStatus = if ($vmObj -and $vmObj.State -eq 'Running') { 'OK' } elseif ($vmObj) { 'WARN' } else { 'FAIL' }

                $vmIp = $m.IP
                if ($m.IsLinux -and $vmObj) {
                    $adapter = Get-VMNetworkAdapter -VMName $m.VMName -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($adapter -and ($adapter.PSObject.Properties.Name -contains 'IPAddresses')) {
                        $liveIp = @($adapter.IPAddresses) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
                        if ($liveIp) { $vmIp = $liveIp }
                    }
                }

                $reportMachines += @{
                    VMName = $m.VMName
                    OSTag  = if ($m.IsLinux) { '[LIN]' } else { '[WIN]' }
                    IP     = $vmIp
                    Roles  = @($m.Tag)
                    Status = $vmStatus
                }
            }

            $reportPath = New-LabDeploymentReport -Machines $reportMachines -LabName $config.LabName -OutputPath $config.LabPath -StartTime $buildStartTime
        }
        catch {
            Write-Host "    [WARN] Report generation failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    catch {
        $buildEnd = Get-Date
        $totalDuration = $buildEnd - $buildStart

        # Build timing data for failure summary
        foreach ($key in $timings.Keys) {
            $timingData[$key] = @{
                Seconds = [math]::Round($timings[$key].TotalSeconds, 1)
                Display = $timings[$key].ToString('hh\:mm\:ss')
            }
        }

        Write-Host ''
        Write-Host ('  ' + ('=' * 55)) -ForegroundColor Red
        Write-Host '  LabBuilder - Build FAILED' -ForegroundColor Red
        Write-Host ('  ' + ('=' * 55)) -ForegroundColor Red
        Write-Host ''
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  At:    $($_.ScriptStackTrace)" -ForegroundColor DarkRed
        Write-Host ''
        Write-Host '  Next Actions:' -ForegroundColor Yellow
        Write-Host '    1. Check the transcript log for details:' -ForegroundColor Gray
        Write-Host "       $transcriptPath" -ForegroundColor Gray
        Write-Host '    2. Resolve the error and re-run Invoke-LabBuilder.ps1' -ForegroundColor Gray
        Write-Host '    3. If VMs are stuck, run: Get-VM | Stop-VM -TurnOff -Force' -ForegroundColor Gray
        Write-Host ''

        # Write failure summary
        $failSummary = @{
            LabName       = $Config.LabName
            BuildTimestamp = $buildStart.ToString('o')
            TotalDuration = @{
                Seconds = [math]::Round($totalDuration.TotalSeconds, 1)
                Display = $totalDuration.ToString('hh\:mm\:ss')
            }
            SelectedRoles = $SelectedRoles
            Success       = $false
            Error         = $_.Exception.Message
            TranscriptLog = $transcriptPath
            Timings       = $timingData
        }
        $failSummary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8

        Stop-Transcript -ErrorAction SilentlyContinue
        throw
    }

    # ================================================================
    # Final: Stop Logging
    # ================================================================
    Stop-Transcript -ErrorAction SilentlyContinue
}
