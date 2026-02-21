if (-not (Get-Command Resolve-LabBuilderConfig -CommandType Function -ErrorAction SilentlyContinue)) {
    $resolveConfigPath = Join-Path $PSScriptRoot 'Resolve-LabBuilderConfig.ps1'
    if (-not (Test-Path $resolveConfigPath)) {
        throw "Missing dependency: $resolveConfigPath"
    }
    . $resolveConfigPath
}

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
        Optional path to a config file (.ps1 or .psd1).
        Defaults to ..\Lab-Config.ps1 (global one-stop config).
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
    # Load shared config first (Lab-Config.ps1 defines variables like $LabSwitch, $DomainName)
    $sharedConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Config.ps1'
    if (Test-Path $sharedConfigPath) { . $sharedConfigPath }
    $sharedCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $sharedCommonPath) { . $sharedCommonPath }

    # Load LabBuilder-specific config (supports global Lab-Config.ps1 and legacy psd1).
    $Config = Resolve-LabBuilderConfig -ConfigPath $ConfigPath
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
        $null = New-Item -Path $logDir -ItemType Directory -Force
        Write-Verbose "Created log directory: $logDir"
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
                Write-Verbose "Removing stale VM '$vmName' (LabBuilder cleanup)..."
            $null = Remove-HyperVVMStale -VMName $vmName -Context 'LabBuilder cleanup'
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
            DHCP       = @{ File = 'DHCP.ps1';           Function = 'Get-LabRole_DHCP' }
            FileServer = @{ File = 'FileServer.ps1';     Function = 'Get-LabRole_FileServer' }
            PrintServer = @{ File = 'PrintServer.ps1';   Function = 'Get-LabRole_PrintServer' }
            Jumpbox    = @{ File = 'Jumpbox.ps1';        Function = 'Get-LabRole_Jumpbox' }
            Client     = @{ File = 'Client.ps1';         Function = 'Get-LabRole_Client' }
            Ubuntu          = @{ File = 'Ubuntu.ps1';            Function = 'Get-LabRole_Ubuntu' }
            WebServerUbuntu = @{ File = 'WebServer.Ubuntu.ps1'; Function = 'Get-LabRole_WebServerUbuntu' }
            DatabaseUbuntu  = @{ File = 'Database.Ubuntu.ps1';  Function = 'Get-LabRole_DatabaseUbuntu' }
            DockerUbuntu    = @{ File = 'Docker.Ubuntu.ps1';    Function = 'Get-LabRole_DockerUbuntu' }
            K8sUbuntu       = @{ File = 'K8s.Ubuntu.ps1';       Function = 'Get-LabRole_K8sUbuntu' }
        }

        $roleDefs = @()
        foreach ($tag in $SelectedRoles) {
            $entry = $roleScriptMap[$tag]
            if (-not $entry) {
                # Unknown to built-in map -- will be handled as custom role below
                continue
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

        # Load custom roles (tags not in $roleScriptMap)
        $customRoleLoaderPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Private'
        $customValidatorPath = Join-Path $customRoleLoaderPath 'Test-LabCustomRoleSchema.ps1'
        $customRoleLoaderPath = Join-Path $customRoleLoaderPath 'Get-LabCustomRole.ps1'

        $customTags = @($SelectedRoles | Where-Object { -not $roleScriptMap.ContainsKey($_) })
        if ($customTags.Count -gt 0) {
            if (Test-Path $customRoleLoaderPath) {
                . $customValidatorPath
                . $customRoleLoaderPath
                foreach ($customTag in $customTags) {
                    $customRole = Get-LabCustomRole -Name $customTag -Config $Config
                    if (-not $customRole) {
                        throw "Custom role not found: $customTag"
                    }
                    $roleDefs += $customRole
                    Write-Host "    [OK] Loaded custom role: $customTag -> $($customRole.VMName)" -ForegroundColor Green
                }
            }
            else {
                throw "Custom role tags specified ($($customTags -join ', ')) but Get-LabCustomRole.ps1 not found at $customRoleLoaderPath"
            }
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
            Write-Verbose "Creating vSwitch '$($net.SwitchName)' (Internal)..."
            $null = New-VMSwitch -Name $net.SwitchName -SwitchType Internal
            Write-Host "    [OK] Created vSwitch: $($net.SwitchName)" -ForegroundColor Green
        }

        # Ensure host gateway IP
        $ifAlias = "vEthernet ($($net.SwitchName))"
        $hasGw = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -eq $net.Gateway }
        if (-not $hasGw) {
            Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Write-Verbose "Setting host gateway IP $($net.Gateway) on $ifAlias..."
            $null = New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $net.Gateway -PrefixLength 24
            Write-Host "    [OK] Set host gateway IP: $($net.Gateway)" -ForegroundColor Green
        }

        # Ensure NAT
        $nat = Get-NetNat -Name $net.NatName -ErrorAction SilentlyContinue
        if (-not $nat) {
            Write-Verbose "Creating NAT '$($net.NatName)' for $($net.AddressSpace)..."
            $null = New-NetNat -Name $net.NatName -InternalIPInterfaceAddressPrefix $net.AddressSpace
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
                $jobLinuxRoleBase = Join-Path $PSScriptRoot 'Roles\LinuxRoleBase.ps1'

                $job = Start-Job -ScriptBlock {
                    param($ConfigData, $CommonPath, $ConfigPath, $LinuxRoleBasePath, $CreateScript)

                    if (Test-Path $ConfigPath) { . $ConfigPath }
                    if (Test-Path $CommonPath) { . $CommonPath }
                    if (Test-Path $LinuxRoleBasePath) { . $LinuxRoleBasePath }

                    $block = [scriptblock]::Create($CreateScript)
                    & $block $ConfigData
                } -ArgumentList $jobConfig, $jobLabCommon, $jobLabConfig, $jobLinuxRoleBase, $createBlock.ToString()

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
        $installStart = Get-Date
        Write-Host "    Started at: $(Get-Date -Format 'HH:mm:ss'). This typically takes 15-45 minutes." -ForegroundColor Gray
        Write-Host '    VMs being deployed:' -ForegroundColor White
        foreach ($rd in $roleDefs) {
            Write-Host "      $($rd.VMName.PadRight(12)) $($rd.IP.PadRight(16)) $($rd.Tag)" -ForegroundColor Gray
        }
        Write-Host ''

        $phaseStart = Get-Date
        Install-Lab -ErrorAction Stop
        $timings['InstallLab'] = (Get-Date) - $phaseStart
        $installElapsed = (Get-Date) - $installStart

        Write-Host '    [OK] Lab installation complete.' -ForegroundColor Green
        Write-Host ("    Install-Lab completed in {0:D2}m {1:D2}s" -f [int]$installElapsed.TotalMinutes, $installElapsed.Seconds) -ForegroundColor Green

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

        # DC must run first (AD services needed by other post-installs) -- DC failure is FATAL
        $dcRole = $roleDefs | Where-Object { $_.Tag -eq 'DC' }
        if ($dcRole -and $dcRole.PostInstall) {
            Write-Host "    Running post-install: $($dcRole.VMName) [CRITICAL - AD services]..." -ForegroundColor Yellow
            try {
                & $dcRole.PostInstall $Config
                Write-Host "    [OK] DC post-install complete: $($dcRole.VMName)" -ForegroundColor Green
            }
            catch {
                throw "FATAL: DC role post-install failed. AD services are required for all other roles. Error: $($_.Exception.Message). Aborting build."
            }
        }

        # Then all other Windows roles (not DC) in parallel
        $postInstallResults = @()
        $windowsPostInstallRoles = @($roleDefs | Where-Object { $_.Tag -ne 'DC' -and -not $_.IsLinux -and $_.PostInstall })
        if ($windowsPostInstallRoles.Count -gt 0) {
            $postInstallJobs = @()

            foreach ($rd in $windowsPostInstallRoles) {
                Write-Host "    Queuing post-install: $($rd.VMName)..." -ForegroundColor Yellow

                $job = Start-Job -ScriptBlock {
                    param($roleDef, $cfg, $commonPath, $labCfgPath)

                    try {
                        if (Test-Path $labCfgPath) { . $labCfgPath }
                        if (Test-Path $commonPath) { . $commonPath }
                        $null = Import-Module AutomatedLab -ErrorAction Stop

                        $block = [scriptblock]::Create($roleDef.PostInstall.ToString())
                        & $block $cfg
                        [pscustomobject]@{ VMName = $roleDef.VMName; Tag = $roleDef.Tag; Success = $true; Error = '' }
                    }
                    catch {
                        [pscustomobject]@{ VMName = $roleDef.VMName; Tag = $roleDef.Tag; Success = $false; Error = $_.Exception.Message }
                    }
                } -ArgumentList $rd, $Config, (Join-Path $PSScriptRoot '..\Lab-Common.ps1'), (Join-Path $PSScriptRoot '..\Lab-Config.ps1')

                $postInstallJobs += $job
            }

            if ($postInstallJobs.Count -gt 0) {
                $null = Wait-Job -Job $postInstallJobs
                foreach ($job in $postInstallJobs) {
                    $jobResult = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    if ($jobResult -and $jobResult.Success) {
                        Write-Host "    [OK] Post-install complete: $($jobResult.VMName)" -ForegroundColor Green
                        $postInstallResults += @{ VMName = $jobResult.VMName; Tag = $jobResult.Tag; Status = 'OK'; Error = '' }
                    }
                    else {
                        $jobName = if ($jobResult) { $jobResult.VMName } else { $job.Name }
                        $jobTag  = if ($jobResult) { $jobResult.Tag }    else { '?' }
                        $jobErr  = if ($jobResult) { $jobResult.Error }  else { 'Unknown post-install failure.' }
                        Write-Warning "Post-install for $jobName failed: $jobErr"
                        $postInstallResults += @{ VMName = $jobName; Tag = $jobTag; Status = 'FAIL'; Error = $jobErr }
                    }
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Custom role provisioning (after Windows post-installs, before Linux)
        $customPostInstallRoles = @($roleDefs | Where-Object { $_.IsCustomRole -eq $true })
        foreach ($rd in $customPostInstallRoles) {
            Write-Host "    Running custom role provisioning: $($rd.VMName) [$($rd.Tag)]..." -ForegroundColor Yellow
            try {
                foreach ($step in $rd.ProvisioningSteps) {
                    switch ($step.type) {
                        'windowsFeature' {
                            Invoke-LabCommand -ComputerName $rd.VMName -ActivityName "CustomRole-$($step.name)" -ScriptBlock {
                                param($FeatureName)
                                Install-WindowsFeature -Name $FeatureName -IncludeManagementTools -ErrorAction Stop
                            } -ArgumentList $step.value -Retries 2 -RetryIntervalInSeconds 15
                        }
                        'powershellScript' {
                            Invoke-LabCommand -ComputerName $rd.VMName -ActivityName "CustomRole-$($step.name)" -ScriptBlock ([scriptblock]::Create($step.value)) -Retries 2 -RetryIntervalInSeconds 15
                        }
                        'linuxCommand' {
                            # Linux commands via SSH - only if IsLinux
                            Write-Warning "Custom role step type 'linuxCommand' not yet wired for $($rd.VMName). Step '$($step.name)' skipped."
                        }
                        default {
                            Write-Warning "Unknown provisioning step type '$($step.type)' in custom role $($rd.Tag). Step '$($step.name)' skipped."
                        }
                    }
                    Write-Host "      [OK] Step: $($step.name)" -ForegroundColor Green
                }
                $postInstallResults += @{ VMName = $rd.VMName; Tag = $rd.Tag; Status = 'OK'; Error = '' }
            }
            catch {
                Write-Warning "Custom role provisioning for $($rd.VMName) failed: $($_.Exception.Message)"
                $postInstallResults += @{ VMName = $rd.VMName; Tag = $rd.Tag; Status = 'FAIL'; Error = $_.Exception.Message }
            }
        }

        # Linux post-installs run after all Windows post-installs
        foreach ($rd in $roleDefs) {
            if (-not $rd.IsLinux) { continue }
            if ($rd.PostInstall) {
                Write-Host "    Running post-install: $($rd.VMName) [Linux]..." -ForegroundColor Yellow
                try {
                    & $rd.PostInstall $Config
                    $postInstallResults += @{ VMName = $rd.VMName; Tag = $rd.Tag; Status = 'OK'; Error = '' }
                }
                catch {
                    Write-Warning "Post-install for $($rd.VMName) failed: $($_.Exception.Message)"
                    $postInstallResults += @{ VMName = $rd.VMName; Tag = $rd.Tag; Status = 'FAIL'; Error = $_.Exception.Message }
                }
            }
        }

        # Post-Install Summary
        if ($postInstallResults.Count -gt 0) {
            Write-Host ''
            Write-Host '    Post-Install Summary:' -ForegroundColor Cyan
            Write-Host '    VM Name      Role            Status' -ForegroundColor White
            Write-Host '    -------      ----            ------' -ForegroundColor Gray
            foreach ($r in $postInstallResults) {
                $statusColor = switch ($r.Status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } default { 'Red' } }
                $statusText = if ($r.Status -eq 'FAIL' -and $r.Error) { "FAIL: $($r.Error.Substring(0, [math]::Min(60, $r.Error.Length)))" } else { $r.Status }
                Write-Host "    $($r.VMName.PadRight(13))$($r.Tag.PadRight(16))$statusText" -ForegroundColor $statusColor
            }
            $failCount = @($postInstallResults | Where-Object { $_.Status -eq 'FAIL' }).Count
            if ($failCount -gt 0) {
                Write-Warning "$failCount of $($postInstallResults.Count) role post-installs failed. Lab may be partially configured."
            }
            Write-Host ''
        }

        $timings['PostInstall'] = (Get-Date) - $phaseStart

        # ============================================================
        # Phase 11.5: Apply STIG Baselines to Member Server VMs (if enabled)
        # ============================================================
        # DC STIG is applied inside DC.ps1 PostInstall block above.
        # This phase applies STIG to all non-DC Windows VMs collectively,
        # using the same ContainsKey guards pattern (StrictMode safe).
        if (Test-Path variable:GlobalLabConfig) {
            if ($GlobalLabConfig.ContainsKey('STIG') -and
                $GlobalLabConfig.STIG.ContainsKey('Enabled') -and
                $GlobalLabConfig.STIG.Enabled) {

                $shouldAutoApply = if ($GlobalLabConfig.STIG.ContainsKey('AutoApplyOnDeploy')) {
                    [bool]$GlobalLabConfig.STIG.AutoApplyOnDeploy
                } else { $true }

                if (-not $shouldAutoApply) {
                    Write-Host '  [SKIP] STIG baselines enabled but AutoApplyOnDeploy is false.' -ForegroundColor Yellow
                }
                else {
                    # Collect non-DC Windows VMs from this deployment
                    $memberVMs = @($roleDefs | Where-Object { $_.Tag -ne 'DC' -and -not $_.IsLinux } | ForEach-Object { $_.VMName })
                    if ($memberVMs.Count -gt 0) {
                        Write-Host '' -ForegroundColor White
                        Write-Host '  [Phase 11.5] Applying STIG baselines to member server VMs...' -ForegroundColor Yellow
                        $phaseStart = Get-Date
                        try {
                            $stigResult = Invoke-LabSTIGBaselineCore -VMName $memberVMs
                            if ($stigResult.VMsFailed -eq 0) {
                                Write-Host "  [OK] STIG baselines applied ($($stigResult.VMsSucceeded) VMs succeeded)." -ForegroundColor Green
                            }
                            else {
                                Write-Warning "STIG baseline application had $($stigResult.VMsFailed) failure(s). Check .planning/stig-compliance.json for details."
                            }
                        }
                        catch {
                            Write-Warning "STIG baseline application failed: $($_.Exception.Message). Lab deployment continues without STIG on member VMs."
                        }
                        $timings['STIGBaselines'] = (Get-Date) - $phaseStart
                    }
                }
            }
        }

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
            Machines           = $machinePlan
            PostInstallResults = $postInstallResults
            Timings            = $timingData
            TranscriptLog      = $transcriptPath
            Success            = $true
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
