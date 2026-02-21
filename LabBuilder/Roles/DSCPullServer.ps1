function Get-LabRole_DSC {
    <#
    .SYNOPSIS
        Returns the DSC Pull Server role definition for LabBuilder.
    .DESCRIPTION
        Defines DSC1 as a plain domain member (no built-in AL role) with a
        comprehensive PostInstall that configures an HTTP DSC Pull Server on
        port 8080 and Compliance Server on port 9080 using xPSDesiredStateConfiguration.
        Idempotent on reruns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'DSC'
        VMName     = $Config.VMNames.DSC
        Roles      = @()                                # Custom post-install, NOT built-in AL role
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.DSC
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Memory     = $Config.ServerVM.Memory
        MinMemory  = $Config.ServerVM.MinMemory
        MaxMemory  = $Config.ServerVM.MaxMemory
        Processors = $Config.ServerVM.Processors
        DomainName = $Config.DomainName
        Network    = $Config.Network.SwitchName

        PostInstall = {
            param([hashtable]$LabConfig)

            # Prerequisite validation: DSCPullServer config section required
            if (-not $LabConfig.ContainsKey('DSCPullServer') -or -not $LabConfig.DSCPullServer) {
                Write-Warning "DSC role prereq check failed: `$LabConfig.DSCPullServer section not found. Add DSCPullServer config (PullPort, CompliancePort, RegistrationKeyDir, RegistrationKeyFile) to Lab-Config.ps1."
                return
            }
            $dscRequiredKeys = @('PullPort', 'CompliancePort', 'RegistrationKeyDir', 'RegistrationKeyFile')
            $dscMissing = @($dscRequiredKeys | Where-Object { -not $LabConfig.DSCPullServer.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$LabConfig.DSCPullServer[$_]) })
            if ($dscMissing.Count -gt 0) {
                Write-Warning "DSC role prereq check failed: Missing config keys in `$LabConfig.DSCPullServer: $($dscMissing -join ', '). Add these to Lab-Config.ps1."
                return
            }

            $dscVMName   = $LabConfig.VMNames.DSC
            $pullPort    = $LabConfig.DSCPullServer.PullPort
            $compPort    = $LabConfig.DSCPullServer.CompliancePort
            $regKeyDir   = $LabConfig.DSCPullServer.RegistrationKeyDir
            $regKeyFile  = $LabConfig.DSCPullServer.RegistrationKeyFile

            # Step A: Install Windows features
            Write-Host '    Step A: Installing Windows features...' -ForegroundColor Gray
            Invoke-LabCommand -ComputerName $dscVMName -ActivityName 'DSC-Install-Features' -ScriptBlock {
                $features = @('Web-Server', 'DSC-Service', 'Web-Mgmt-Tools')
                foreach ($f in $features) {
                    $feat = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
                    if ($feat -and $feat.InstallState -ne 'Installed') {
                        Install-WindowsFeature -Name $f -IncludeManagementTools -ErrorAction Stop
                        Write-Host "    [OK] Installed feature: $f" -ForegroundColor Green
                    }
                    else {
                        Write-Host "    [OK] Feature already installed: $f" -ForegroundColor Green
                    }
                }
            } -Retries 2 -RetryIntervalInSeconds 10

            # Step B: Install NuGet provider + xPSDesiredStateConfiguration
            Write-Host '    Step B: Installing DSC modules...' -ForegroundColor Gray
            Invoke-LabCommand -ComputerName $dscVMName -ActivityName 'DSC-Install-Modules' -ScriptBlock {
                # NuGet provider (idempotent)
                if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                    Write-Verbose "Installing NuGet provider..."
                    $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                    Write-Host '    [OK] NuGet provider installed.' -ForegroundColor Green
                }

                # Trust PSGallery (idempotent)
                $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
                if ($repo -and $repo.InstallationPolicy -ne 'Trusted') {
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                    Write-Host '    [OK] PSGallery set to Trusted.' -ForegroundColor Green
                }

                # Install module (idempotent)
                if (-not (Get-Module -ListAvailable -Name xPSDesiredStateConfiguration)) {
                    Install-Module -Name xPSDesiredStateConfiguration -Force -Scope AllUsers
                    Write-Host '    [OK] xPSDesiredStateConfiguration installed.' -ForegroundColor Green
                }
                else {
                    Write-Host '    [OK] xPSDesiredStateConfiguration already installed.' -ForegroundColor Green
                }
            } -Retries 2 -RetryIntervalInSeconds 15

            # Step C: Generate registration key (idempotent -- skip if file exists)
            Write-Host '    Step C: Ensuring registration key...' -ForegroundColor Gray
            Invoke-LabCommand -ComputerName $dscVMName -ActivityName 'DSC-Generate-RegistrationKey' -ScriptBlock {
                param($KeyDir, $KeyFile)
                $keyPath = Join-Path $KeyDir $KeyFile
                if (-not (Test-Path $keyPath)) {
                    $null = New-Item -Path $KeyDir -ItemType Directory -Force
                    Write-Verbose "Created DSC registration key directory: $KeyDir"
                    $key = [guid]::NewGuid().Guid
                    Set-Content -Path $keyPath -Value $key -Encoding ASCII -Force
                    Write-Host "    [OK] Registration key generated: $keyPath" -ForegroundColor Green
                }
                else {
                    Write-Host "    [OK] Registration key already exists: $keyPath" -ForegroundColor Green
                }
            } -ArgumentList $regKeyDir, $regKeyFile

            # Step D: Apply DSC configuration for Pull Server endpoints
            Write-Host '    Step D: Configuring Pull Server endpoints...' -ForegroundColor Gray
            Invoke-LabCommand -ComputerName $dscVMName -ActivityName 'DSC-Configure-PullServer' -ScriptBlock {
                param($PullPort, $CompliancePort, $RegKeyDir, $RegKeyFile)

                # Ensure module is importable
                Import-Module xPSDesiredStateConfiguration -ErrorAction Stop

                # Define DSC configuration
                Configuration DscPullServerConfig {
                    param([string]$NodeName = 'localhost')

                    Import-DscResource -ModuleName PSDesiredStateConfiguration
                    Import-DscResource -ModuleName xPSDesiredStateConfiguration

                    Node $NodeName {
                        WindowsFeature IIS {
                            Ensure = 'Present'
                            Name   = 'Web-Server'
                        }

                        WindowsFeature DSCService {
                            Ensure    = 'Present'
                            Name      = 'DSC-Service'
                            DependsOn = '[WindowsFeature]IIS'
                        }

                        xDscWebService PSDSCPullServer {
                            Ensure                       = 'Present'
                            EndpointName                 = 'PSDSCPullServer'
                            Port                         = $PullPort
                            PhysicalPath                 = "$env:SystemDrive\inetpub\PSDSCPullServer"
                            CertificateThumbPrint        = 'AllowUnencryptedTraffic'
                            ModulePath                   = "$env:ProgramFiles\WindowsPowerShell\DscService\Modules"
                            ConfigurationPath            = "$env:ProgramFiles\WindowsPowerShell\DscService\Configuration"
                            RegistrationKeyPath          = $RegKeyDir
                            State                        = 'Started'
                            UseSecurityBestPractices      = $false
                            DependsOn                    = '[WindowsFeature]DSCService'
                        }

                        xDscWebService PSDSCComplianceServer {
                            Ensure                       = 'Present'
                            EndpointName                 = 'PSDSCComplianceServer'
                            Port                         = $CompliancePort
                            PhysicalPath                 = "$env:SystemDrive\inetpub\PSDSCComplianceServer"
                            CertificateThumbPrint        = 'AllowUnencryptedTraffic'
                            State                        = 'Started'
                            IsComplianceServer           = $true
                            UseSecurityBestPractices      = $false
                            DependsOn                    = '[xDscWebService]PSDSCPullServer'
                        }

                        File RegistrationKeyDir {
                            Ensure          = 'Present'
                            Type            = 'Directory'
                            DestinationPath = $RegKeyDir
                        }
                    }
                }

                # Compile MOF
                $mofOutputPath = "$env:TEMP\DscPullServerConfig"
                if (Test-Path $mofOutputPath) { Remove-Item $mofOutputPath -Recurse -Force }
                Write-Verbose "Compiling DSC Pull Server MOF to $mofOutputPath..."
                $null = DscPullServerConfig -NodeName 'localhost' -OutputPath $mofOutputPath

                # Apply configuration
                Start-DscConfiguration -Path $mofOutputPath -Wait -Verbose -Force

                Write-Host "    [OK] Pull Server configured on port $PullPort" -ForegroundColor Green
                Write-Host "    [OK] Compliance Server configured on port $CompliancePort" -ForegroundColor Green

                # Open firewall ports (idempotent)
                $pullRule = Get-NetFirewallRule -DisplayName "DSC Pull Server ($PullPort)" -ErrorAction SilentlyContinue
                if (-not $pullRule) {
                    Write-Verbose "Creating firewall rule for DSC Pull Server port $PullPort..."
                    $null = New-NetFirewallRule -DisplayName "DSC Pull Server ($PullPort)" `
                        -Direction Inbound -LocalPort $PullPort -Protocol TCP -Action Allow
                    Write-Host "    [OK] Firewall rule created for port $PullPort" -ForegroundColor Green
                }

                $compRule = Get-NetFirewallRule -DisplayName "DSC Compliance ($CompliancePort)" -ErrorAction SilentlyContinue
                if (-not $compRule) {
                    Write-Verbose "Creating firewall rule for DSC Compliance Server port $CompliancePort..."
                    $null = New-NetFirewallRule -DisplayName "DSC Compliance ($CompliancePort)" `
                        -Direction Inbound -LocalPort $CompliancePort -Protocol TCP -Action Allow
                    Write-Host "    [OK] Firewall rule created for port $CompliancePort" -ForegroundColor Green
                }
            } -ArgumentList $pullPort, $compPort, $regKeyDir, $regKeyFile -Retries 2 -RetryIntervalInSeconds 30
        }
    }
}


function Set-LabLCMPullMode {
    <#
    .SYNOPSIS
        Configures a client VM's LCM to use the DSC Pull Server.
    .DESCRIPTION
        Sets the Local Configuration Manager on the specified client VM to Pull mode,
        pointing at the DSC1 Pull Server with the shared registration key.
        Uses HTTP (AllowUnsecureConnection) for lab environments.
    .EXAMPLE
        Set-LabLCMPullMode -ClientVMName 'WIN10-01' -PullServerIP '10.0.10.40' -PullServerPort 8080 -RegistrationKey 'abc123' -ConfigurationName 'ClientConfig'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClientVMName,

        [Parameter(Mandatory)]
        [string]$PullServerIP,

        [Parameter(Mandatory)]
        [int]$PullServerPort,

        [Parameter(Mandatory)]
        [string]$RegistrationKey,

        [Parameter(Mandatory)]
        [string]$ConfigurationName
    )

    $serverUrl = "http://${PullServerIP}:${PullServerPort}/PSDSCPullServer.svc"
    Write-Host "  Configuring LCM Pull mode on $ClientVMName -> $serverUrl" -ForegroundColor Yellow

    Invoke-LabCommand -ComputerName $ClientVMName -ActivityName "LCM-PullMode-$ClientVMName" -ScriptBlock {
        param($ServerUrl, $RegKey, $ConfigName)

        [DSCLocalConfigurationManager()]
        Configuration LCMPullConfig {
            Node 'localhost' {
                Settings {
                    RefreshMode          = 'Pull'
                    RefreshFrequencyMins = 30
                    RebootNodeIfNeeded   = $true
                    ConfigurationMode    = 'ApplyAndAutoCorrect'
                }
                ConfigurationRepositoryWeb PullServer {
                    ServerURL               = $ServerUrl
                    RegistrationKey         = $RegKey
                    ConfigurationNames      = @($ConfigName)
                    AllowUnsecureConnection = $true
                }
            }
        }

        $mofPath = "$env:TEMP\LCMPullConfig"
        if (Test-Path $mofPath) { Remove-Item $mofPath -Recurse -Force }
        Write-Verbose "Compiling LCM Pull Config MOF to $mofPath..."
        $null = LCMPullConfig -OutputPath $mofPath
        Set-DscLocalConfigurationManager -Path $mofPath -Force -Verbose

        Write-Host "  [OK] LCM configured for Pull mode on $env:COMPUTERNAME" -ForegroundColor Green
    } -ArgumentList $serverUrl, $RegistrationKey, $ConfigurationName
}
