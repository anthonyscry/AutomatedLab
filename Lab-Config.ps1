# Lab-Config.ps1 -- Global one-stop configuration for the entire repository
#
# Edit this file to customize lab behavior. Every setting includes a comment
# describing what changes when you modify it.
#
# Backward compatibility note:
# - Existing scripts still consume legacy variables like $LabName, $LabSwitch,
#   $AdminPassword, etc.
# - This file now defines structured hashtables first, then exports those
#   legacy variables so older scripts keep working.

$defaultLabName = 'AutomatedLab'
$defaultDomainName = 'simplelab.local'
$defaultSwitchName = 'AutomatedLab'
$defaultSqlSaPassword = 'SimpleLabSqlSa123!'

$GlobalLabConfig = @{
    Lab = @{
        # Changing Name renames the core lab identity used by app actions.
        Name = $defaultLabName

        # Changing CoreVMNames alters which VMs are targeted by default for
        # start/stop/status flows in scripts that operate on the "core lab".
        CoreVMNames = @('dc1', 'svr1', 'ws1')

        # Changing DomainName updates the AD domain used for joins and reports.
        DomainName = $defaultDomainName

        # Changing TimeZone affects guest timezone configuration where applied.
        TimeZone = try { [System.TimeZoneInfo]::Local.Id } catch { 'Pacific Standard Time' }
    }

    Paths = @{
        # Changing LabRoot moves where lab VM files/checkpoints are stored.
        LabRoot = 'C:\AutomatedLab'

        # Changing LabSourcesRoot moves shared ISOs, scripts, logs, and reports.
        LabSourcesRoot = 'C:\LabSources'

        # Changing ShareName changes the SMB share name exposed to clients/Linux.
        ShareName = 'LabShare'

        # Changing SharePath changes the host folder path backing ShareName.
        SharePath = 'C:\LabShare'

        # Changing GitRepoPath changes where mirrored project repos are staged.
        GitRepoPath = 'C:\LabShare\GitRepo'

        # Changing LinuxLabShareMount changes where Linux mounts the SMB share.
        LinuxLabShareMount = '/mnt/labshare'

        # Changing LinuxProjectsRoot changes default Linux project workspace path.
        LinuxProjectsRoot = '/home/labadmin/projects'
    }

    Credentials = @{
        # Changing InstallUser changes the username used for domain admin tasks.
        InstallUser = 'admin'

        # Changing AdminPassword changes the fallback password used by scripts.
        # Prefer environment variable usage for secrets in shared environments.
        AdminPassword = 'SimpleLab123!'

        # Changing PasswordEnvVar changes which env var Resolve-LabPassword uses.
        PasswordEnvVar = 'OPENCODELAB_ADMIN_PASSWORD'

        # Changing BuilderPasswordEnvVar changes LabBuilder's password env var.
        BuilderPasswordEnvVar = 'LAB_ADMIN_PASSWORD'

        # Changing SqlSaPassword changes SQL authentication login password for `sa`.
        SqlSaPassword = $defaultSqlSaPassword

        # Changing LinuxUser changes the default Linux SSH/domain join user.
        LinuxUser = 'labadmin'

        # Changing GitName/GitEmail sets defaults for non-interactive git flows.
        GitName = ''
        GitEmail = ''
    }

    Network = @{
        # Changing SwitchName changes the Hyper-V internal switch name.
        SwitchName = $defaultSwitchName

        # Changing AddressSpace changes the lab subnet CIDR used by NAT/network.
        AddressSpace = '10.0.10.0/24'

        # Changing GatewayIp changes the host vEthernet gateway for the subnet.
        GatewayIp = '10.0.10.1'

        # Changing NatName changes the host NAT object name.
        NatName = "${defaultSwitchName}NAT"

        # Changing DnsIp changes default DNS resolver provided to guests.
        DnsIp = '10.0.10.10'
    }

    IPPlan = @{
        # Changing these IPs remaps static addressing for core VMs.
        DC1  = '10.0.10.10'
        SVR1 = '10.0.10.20'
        WS1  = '10.0.10.30'
        DSC1 = '10.0.10.40'
        LIN1 = '10.0.10.110'
    }

    VMSizing = @{
        # Changing any Memory/CPU values changes VM hardware defaults.
        DC = @{
            Memory = 4GB
            MinMemory = 2GB
            MaxMemory = 6GB
            Processors = 4
        }
        Server = @{
            Memory = 4GB
            MinMemory = 2GB
            MaxMemory = 6GB
            Processors = 4
        }
        Client = @{
            Memory = 4GB
            MinMemory = 2GB
            MaxMemory = 6GB
            Processors = 4
        }
        DSC = @{
            Memory = 4GB
            MinMemory = 2GB
            MaxMemory = 6GB
            Processors = 4
        }
        Ubuntu = @{
            Memory = 2GB
            MinMemory = 1GB
            MaxMemory = 4GB
            Processors = 2
        }
    }

    DHCP = @{
        # Changing these values changes DHCP scope served from DC for Linux nodes.
        ScopeId = '10.0.10.0'
        Start = '10.0.10.100'
        End = '10.0.10.200'
        Mask = '255.255.255.0'
    }

    Timeouts = @{
        AutomatedLab = @{
            # Changing these values adjusts long-running AL operation timeouts.
            DcRestart = 90
            AdwsReady = 120
            StartVM = 90
            WaitVM = 90
        }
        Linux = @{
            # Changing these values adjusts Linux SSH wait/retry behavior.
            LIN1WaitMinutes = 30
            SSHConnectTimeout = 8
            SSHPollInitialSec = 10
            SSHPollMaxSec = 30
        }
    }

    AutoHeal = @{
        # Changing Enabled toggles whether quick-mode auto-heal runs before fallback.
        Enabled = $true
        # Changing TimeoutSeconds caps total heal duration before aborting.
        TimeoutSeconds = 120
        # Changing HealthCheckTimeoutSeconds caps VM health verification for LabReady healing.
        HealthCheckTimeoutSeconds = 60
    }

    SoftwarePackages = @{
        Git = @{
            Version = '2.47.1.2'
            InstallerFileName = 'Git-2.47.1.2-64-bit.exe'
            DownloadUrl = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe'
            Sha256 = '0229E3ACB535D0DC5F0D4A7E33CD36E3E3BA5B67A44B507B4D5E6A63B0B8BBDE'
        }
    }

    # Changing RequiredISOs changes which local ISO filenames are required.
    RequiredISOs = @('server2019.iso', 'windows11.iso')

    Builder = @{
        # Changing LabName changes the AutomatedLab definition name for LabBuilder runs.
        LabName = 'LabBuilder'

        # Changing DomainName changes domain for LabBuilder-managed machines.
        DomainName = $defaultDomainName

        # Changing LabPath changes where LabBuilder VM artifacts are stored.
        LabPath = 'C:\AutomatedLab\LabBuilder'

        # Changing LabSourcesRoot changes where LabBuilder searches for ISOs/assets.
        LabSourcesRoot = 'C:\LabSources'

        Network = @{
            # Changing SwitchName changes LabBuilder's dedicated switch.
            SwitchName = 'LabBuilder'

            # Changing AddressSpace changes LabBuilder subnet CIDR.
            AddressSpace = '10.0.10.0/24'

            # Changing Gateway changes host gateway IP used for LabBuilder subnet.
            Gateway = '10.0.10.1'

            # Changing DnsServer changes DNS IP given to Builder VMs.
            DnsServer = '10.0.10.10'

            # Changing NatName changes LabBuilder NAT object name.
            NatName = 'LabBuilderNAT'
        }

        IPPlan = @{
            # Changing these values remaps static IP allocation by role tag.
            DC = '10.0.10.10'
            DSC = '10.0.10.40'
            IIS = '10.0.10.50'
            SQL = '10.0.10.60'
            WSUS = '10.0.10.70'
            DHCP = '10.0.10.75'
            FileServer = '10.0.10.80'
            PrintServer = '10.0.10.85'
            Jumpbox = '10.0.10.90'
            Client = '10.0.10.100'
            Ubuntu = '10.0.10.110'
            WebServerUbuntu = '10.0.10.111'
            DatabaseUbuntu = '10.0.10.112'
            DockerUbuntu = '10.0.10.113'
            K8sUbuntu = '10.0.10.114'
        }

        VMNames = @{
            # Changing these values renames VMs generated for each role tag.
            DC = 'DC1'
            DSC = 'DSC1'
            IIS = 'IIS1'
            SQL = 'SQL1'
            WSUS = 'WSUS1'
            DHCP = 'DHCP1'
            FileServer = 'FILE1'
            PrintServer = 'PRN1'
            Jumpbox = 'JUMP1'
            Client = 'WIN10-01'
            Ubuntu = 'LIN1'
            WebServerUbuntu = 'LINWEB1'
            DatabaseUbuntu = 'LINDB1'
            DockerUbuntu = 'LINDOCK1'
            K8sUbuntu = 'LINK8S1'
        }

        # Changing these values changes default OS selection in role definitions.
        ServerOS = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
        ClientOS = 'Windows 11 Enterprise Evaluation'
        LinuxOS = 'Ubuntu 24.04 LTS'

        SupportedDistros = @{
            # Changing ISOPattern alters which ISO filenames are auto-detected.
            Ubuntu2404 = @{
                DisplayName = 'Ubuntu Server 24.04 LTS'
                ISOPattern = 'ubuntu-24.04*.iso'
                CloudInit = 'autoinstall'
            }
            Ubuntu2204 = @{
                DisplayName = 'Ubuntu Server 22.04 LTS'
                ISOPattern = 'ubuntu-22.04*.iso'
                CloudInit = 'autoinstall'
            }
            Rocky9 = @{
                DisplayName = 'Rocky Linux 9'
                ISOPattern = 'Rocky-9*.iso'
                CloudInit = 'nocloud'
            }
        }

        ServerVM = @{
            # Changing these values changes default hardware for Windows server roles.
            Memory = 4GB
            MinMemory = 2GB
            MaxMemory = 6GB
            Processors = 4
        }
        ClientVM = @{
            # Changing these values changes default hardware for client/jumpbox roles.
            Memory = 4GB
            MinMemory = 2GB
            MaxMemory = 6GB
            Processors = 4
        }
        LinuxVM = @{
            # Changing these values changes default hardware for Linux role VMs.
            Memory = 2GB
            MinMemory = 1GB
            MaxMemory = 4GB
            Processors = 2
        }

        Timeouts = @{
            # Changing these values changes LabBuilder-specific timeout behavior.
            DcRestart = 90
            AdwsReady = 120
            StartVM = 90
            WaitVM = 90
            LinuxSSHWait = 30
            SSHConnectTimeout = 8
            SSHPollInitialSec = 10
            SSHPollMaxSec = 30
        }

        # Changing CredentialEnvVar changes env var checked for Builder password.
        CredentialEnvVar = 'LAB_ADMIN_PASSWORD'

        # Changing CredentialUser changes Builder admin username.
        CredentialUser = 'Administrator'

        # Changing RequiredISOs changes Builder ISO preflight requirements.
        RequiredISOs = @('server2019.iso', 'windows11.iso')

        SQL = @{
            # Changing IsoPattern changes which SQL Server ISO filename is selected.
            IsoPattern = 'sql*.iso'

            # Changing InstanceName changes SQL instance name (MSSQLSERVER = default instance).
            InstanceName = 'MSSQLSERVER'

            # Changing Features changes SQL features installed by setup.
            Features = 'SQLENGINE'

            # Changing SaPassword changes SQL authentication `sa` password for setup.
            SaPassword = $defaultSqlSaPassword

            # Changing TcpPort changes inbound SQL firewall port opened after install.
            TcpPort = 1433
        }

        WSUS = @{
            # Changing ContentDir changes where WSUS stores update content on disk.
            ContentDir = 'C:\WSUS'

            # Changing Port changes the WSUS HTTP endpoint validation port.
            Port = 8530
        }

        DSCPullServer = @{
            # Changing these values updates DSC pull/compliance endpoint settings.
            PullPort = 8080
            CompliancePort = 9080
            RegistrationKeyDir = 'C:\DscPull\RegistrationKeys'
            RegistrationKeyFile = 'RegistrationKey.txt'
            ModulePath = 'C:\Program Files\WindowsPowerShell\DscService\Modules'
            ConfigurationPath = 'C:\Program Files\WindowsPowerShell\DscService\Configuration'
        }

        Linux = @{
            # Changing these values affects Linux SSH identity and shared path mapping.
            User = 'labadmin'
            SSHKeyDir = 'C:\LabSources\SSHKeys'
            SSHPublicKey = 'C:\LabSources\SSHKeys\id_ed25519.pub'
            SSHPrivateKey = 'C:\LabSources\SSHKeys\id_ed25519'
            LabShareMount = '/mnt/labshare'
            ProjectsRoot = '/home/labadmin/projects'
            ShareName = 'LabShare'
            SharePath = 'C:\LabShare'
            GitRepoPath = 'C:\LabShare\GitRepo'
        }

        DHCP = @{
            # Changing these values updates DHCP range used for Linux leases.
            ScopeId = '10.0.10.0'
            Start = '10.0.10.100'
            End = '10.0.10.200'
            Mask = '255.255.255.0'
        }

        # Changing RoleMenu controls what appears in the interactive Builder menu.
        RoleMenu = @(
            @{ Tag = 'DC'; Label = 'Domain Controller (DC1) + DNS + CA'; Locked = $true }
            @{ Tag = 'DSC'; Label = 'DSC Pull Server (DSC1)'; Locked = $false }
            @{ Tag = 'IIS'; Label = 'IIS Web Server (IIS1)'; Locked = $false }
            @{ Tag = 'SQL'; Label = 'SQL Server (SQL1)'; Locked = $false }
            @{ Tag = 'WSUS'; Label = 'WSUS (WSUS1)'; Locked = $false }
            @{ Tag = 'DHCP'; Label = 'DHCP Server (DHCP1)'; Locked = $false }
            @{ Tag = 'FileServer'; Label = 'File Server (FILE1)'; Locked = $false }
            @{ Tag = 'PrintServer'; Label = 'Print Server (PRN1)'; Locked = $false }
            @{ Tag = 'Jumpbox'; Label = 'Jumpbox/Admin (JUMP1)'; Locked = $false }
            @{ Tag = 'Client'; Label = 'Client VM (WIN10-01)'; Locked = $false }
            @{ Separator = $true; Label = '-- Linux VMs --' }
            @{ Tag = 'Ubuntu'; Label = 'Ubuntu Server (LIN1)'; Locked = $false }
            @{ Tag = 'WebServerUbuntu'; Label = 'Web Server (Ubuntu/nginx)'; Default = $false }
            @{ Tag = 'DatabaseUbuntu'; Label = 'Database (Ubuntu/PostgreSQL)'; Default = $false }
            @{ Tag = 'DockerUbuntu'; Label = 'Docker (Ubuntu)'; Default = $false }
            @{ Tag = 'K8sUbuntu'; Label = 'Kubernetes (Ubuntu/k3s)'; Default = $false }
        )
    }
}

# -----------------------------------------------------------------------------
# Legacy variable exports (existing scripts rely on these variable names)
# -----------------------------------------------------------------------------

# Lab identity
$LabName = $GlobalLabConfig.Lab.Name
$LabVMs = @($GlobalLabConfig.Lab.CoreVMNames)
$DomainName = $GlobalLabConfig.Lab.DomainName

# Lab paths
$LabPath = Join-Path $GlobalLabConfig.Paths.LabRoot $LabName
$LabSourcesRoot = $GlobalLabConfig.Paths.LabSourcesRoot
$ScriptsRoot = Join-Path $LabSourcesRoot 'Scripts'

# Networking
$LabSwitch = $GlobalLabConfig.Network.SwitchName
$AddressSpace = $GlobalLabConfig.Network.AddressSpace
$GatewayIp = $GlobalLabConfig.Network.GatewayIp
$NatName = $GlobalLabConfig.Network.NatName

# Static IP plan
$dc1_Ip = $GlobalLabConfig.IPPlan.DC1
$svr1_Ip = $GlobalLabConfig.IPPlan.SVR1
$ws1_Ip = $GlobalLabConfig.IPPlan.WS1
$dsc_Ip = $GlobalLabConfig.IPPlan.DSC1
$DnsIp = $GlobalLabConfig.Network.DnsIp

# Legacy aliases (for backward compatibility)
$DC1_Ip = $dc1_Ip
$Server1_Ip = $svr1_Ip
$Win11_Ip = $ws1_Ip

# VM sizing
$DC_Memory = $GlobalLabConfig.VMSizing.DC.Memory
$DC_MinMemory = $GlobalLabConfig.VMSizing.DC.MinMemory
$DC_MaxMemory = $GlobalLabConfig.VMSizing.DC.MaxMemory
$DC_Processors = $GlobalLabConfig.VMSizing.DC.Processors

$Server_Memory = $GlobalLabConfig.VMSizing.Server.Memory
$Server_MinMemory = $GlobalLabConfig.VMSizing.Server.MinMemory
$Server_MaxMemory = $GlobalLabConfig.VMSizing.Server.MaxMemory
$Server_Processors = $GlobalLabConfig.VMSizing.Server.Processors

$Client_Memory = $GlobalLabConfig.VMSizing.Client.Memory
$Client_MinMemory = $GlobalLabConfig.VMSizing.Client.MinMemory
$Client_MaxMemory = $GlobalLabConfig.VMSizing.Client.MaxMemory
$Client_Processors = $GlobalLabConfig.VMSizing.Client.Processors

$DSC_Memory = $GlobalLabConfig.VMSizing.DSC.Memory
$DSC_MinMemory = $GlobalLabConfig.VMSizing.DSC.MinMemory
$DSC_MaxMemory = $GlobalLabConfig.VMSizing.DSC.MaxMemory
$DSC_Processors = $GlobalLabConfig.VMSizing.DSC.Processors

# Credentials
$LabInstallUser = $GlobalLabConfig.Credentials.InstallUser
$AdminPassword = $GlobalLabConfig.Credentials.AdminPassword
$SqlSaPassword = $GlobalLabConfig.Credentials.SqlSaPassword
$LinuxUser = $GlobalLabConfig.Credentials.LinuxUser
if ($AdminPassword -eq 'SimpleLab123!') {
    Write-Warning "[Lab-Config] AdminPassword is set to the default value. Set the '$($GlobalLabConfig.Credentials.PasswordEnvVar)' environment variable or update Lab-Config.ps1 for production use."
}
$GitName = $GlobalLabConfig.Credentials.GitName
$GitEmail = $GlobalLabConfig.Credentials.GitEmail

# Required ISOs
$RequiredISOs = @($GlobalLabConfig.RequiredISOs)

# AutomatedLab timeout overrides (minutes)
$AL_Timeout_DcRestart = $GlobalLabConfig.Timeouts.AutomatedLab.DcRestart
$AL_Timeout_AdwsReady = $GlobalLabConfig.Timeouts.AutomatedLab.AdwsReady
$AL_Timeout_StartVM = $GlobalLabConfig.Timeouts.AutomatedLab.StartVM
$AL_Timeout_WaitVM = $GlobalLabConfig.Timeouts.AutomatedLab.WaitVM

# Linux VM static IPs
$lin1_Ip = $GlobalLabConfig.IPPlan.LIN1
$LIN1_Ip = $lin1_Ip

# Ubuntu VM sizing
$UBU_Memory = $GlobalLabConfig.VMSizing.Ubuntu.Memory
$UBU_MinMemory = $GlobalLabConfig.VMSizing.Ubuntu.MinMemory
$UBU_MaxMemory = $GlobalLabConfig.VMSizing.Ubuntu.MaxMemory
$UBU_Processors = $GlobalLabConfig.VMSizing.Ubuntu.Processors

# DHCP scope
$DhcpScopeId = $GlobalLabConfig.DHCP.ScopeId
$DhcpStart = $GlobalLabConfig.DHCP.Start
$DhcpEnd = $GlobalLabConfig.DHCP.End
$DhcpMask = $GlobalLabConfig.DHCP.Mask

# SSH / Linux identity
$SSHKeyDir = Join-Path $LabSourcesRoot 'SSHKeys'
$SSHPublicKey = Join-Path $SSHKeyDir 'id_ed25519.pub'
$SSHPrivateKey = Join-Path $SSHKeyDir 'id_ed25519'

# Share paths
$ShareName = $GlobalLabConfig.Paths.ShareName
$SharePath = $GlobalLabConfig.Paths.SharePath
$GitRepoPath = $GlobalLabConfig.Paths.GitRepoPath

# Linux paths
$LinuxLabShareMount = $GlobalLabConfig.Paths.LinuxLabShareMount
$LinuxProjectsRoot = $GlobalLabConfig.Paths.LinuxProjectsRoot

# Linux-specific timeouts
$LIN1_WaitMinutes = $GlobalLabConfig.Timeouts.Linux.LIN1WaitMinutes
$SSH_ConnectTimeout = $GlobalLabConfig.Timeouts.Linux.SSHConnectTimeout
$SSH_PollInitialSec = $GlobalLabConfig.Timeouts.Linux.SSHPollInitialSec
$SSH_PollMaxSec = $GlobalLabConfig.Timeouts.Linux.SSHPollMaxSec

# Timezone
$LabTimeZone = $GlobalLabConfig.Lab.TimeZone

# Expose Builder config as a first-class variable for LabBuilder loaders.
$LabBuilderConfig = $GlobalLabConfig.Builder

$GitPackageConfig = $GlobalLabConfig.SoftwarePackages.Git
