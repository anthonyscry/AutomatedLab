# LEGACY OVERRIDE FILE:
# - LabBuilder now defaults to ..\Lab-Config.ps1 as the global one-stop config.
# - This file is still supported when passed explicitly with -ConfigPath.
# - Keep this file only if you need a Builder-only override profile.
@{
    # ── Lab Identity ──
    LabName        = 'LabBuilder'
    DomainName     = 'simplelab.local'
    LabPath        = 'C:\AutomatedLab\LabBuilder'
    LabSourcesRoot = 'C:\LabSources'

    # ── Networking ──
    Network = @{
        SwitchName   = 'LabBuilder'
        AddressSpace = '10.0.10.0/24'
        Gateway      = '10.0.10.1'
        DnsServer    = '10.0.10.10'
        NatName      = 'LabBuilderNAT'
    }

    # ── Static IP Plan (keyed by role tag) ──
    IPPlan = @{
        DC         = '10.0.10.10'
        DSC        = '10.0.10.40'
        IIS        = '10.0.10.50'
        SQL        = '10.0.10.60'
        WSUS       = '10.0.10.70'
        DHCP       = '10.0.10.75'
        FileServer = '10.0.10.80'
        PrintServer = '10.0.10.85'
        Jumpbox    = '10.0.10.90'
        Client     = '10.0.10.100'
        Ubuntu     = '10.0.10.110'
        WebServerUbuntu = '10.0.10.111'
        DatabaseUbuntu  = '10.0.10.112'
        DockerUbuntu    = '10.0.10.113'
        K8sUbuntu       = '10.0.10.114'
    }

    # ── VM Names (keyed by role tag) ──
    VMNames = @{
        DC         = 'DC1'
        DSC        = 'DSC1'
        IIS        = 'IIS1'
        SQL        = 'SQL1'
        WSUS       = 'WSUS1'
        DHCP       = 'DHCP1'
        FileServer = 'FILE1'
        PrintServer = 'PRN1'
        Jumpbox    = 'JUMP1'
        Client     = 'WIN10-01'
        Ubuntu     = 'LIN1'
        WebServerUbuntu = 'LINWEB1'
        DatabaseUbuntu  = 'LINDB1'
        DockerUbuntu    = 'LINDOCK1'
        K8sUbuntu       = 'LINK8S1'
    }

    # ── OS Images ──
    ServerOS = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
    ClientOS = 'Windows 11 Enterprise Evaluation'
    LinuxOS  = 'Ubuntu 24.04 LTS'

    # Supported Linux distributions
    SupportedDistros = @{
        Ubuntu2404 = @{
            DisplayName = 'Ubuntu Server 24.04 LTS'
            ISOPattern  = 'ubuntu-24.04*.iso'
            CloudInit   = 'autoinstall'    # Subiquity autoinstall format
        }
        Ubuntu2204 = @{
            DisplayName = 'Ubuntu Server 22.04 LTS'
            ISOPattern  = 'ubuntu-22.04*.iso'
            CloudInit   = 'autoinstall'
        }
        Rocky9 = @{
            DisplayName = 'Rocky Linux 9'
            ISOPattern  = 'Rocky-9*.iso'
            CloudInit   = 'nocloud'        # Standard cloud-init NoCloud
        }
    }

    # ── VM Sizing Defaults ──
    ServerVM = @{
        Memory     = 4GB
        MinMemory  = 2GB
        MaxMemory  = 6GB
        Processors = 4
    }
    ClientVM = @{
        Memory     = 4GB
        MinMemory  = 2GB
        MaxMemory  = 6GB
        Processors = 4
    }
    LinuxVM = @{
        Memory     = 2GB
        MinMemory  = 1GB
        MaxMemory  = 4GB
        Processors = 2
    }

    # ── AutomatedLab Timeout Overrides (minutes) ──
    Timeouts = @{
        DcRestart = 90
        AdwsReady = 120
        StartVM   = 90
        WaitVM    = 90
        LinuxSSHWait      = 30
        SSHConnectTimeout = 8
        SSHPollInitialSec = 10
        SSHPollMaxSec     = 30
    }

    # ── Credentials ──
    CredentialEnvVar = 'LAB_ADMIN_PASSWORD'
    CredentialUser   = 'Administrator'

    # ── Required ISOs ──
    RequiredISOs = @('server2019.iso', 'windows11.iso')

    # ── SQL Role Settings ──
    SQL = @{
        IsoPattern   = 'sql*.iso'
        InstanceName = 'MSSQLSERVER'
        Features     = 'SQLENGINE'
        SaPassword   = 'SimpleLabSqlSa123!'
        TcpPort      = 1433
    }

    # ── WSUS Role Settings ──
    WSUS = @{
        ContentDir = 'C:\WSUS'
        Port       = 8530
    }

    # ── DSC Pull Server Settings ──
    DSCPullServer = @{
        PullPort            = 8080
        CompliancePort      = 9080
        RegistrationKeyDir  = 'C:\DscPull\RegistrationKeys'
        RegistrationKeyFile = 'RegistrationKey.txt'
        ModulePath          = 'C:\Program Files\WindowsPowerShell\DscService\Modules'
        ConfigurationPath   = 'C:\Program Files\WindowsPowerShell\DscService\Configuration'
    }

    # ── Linux Settings ──
    Linux = @{
        User              = 'labadmin'
        SSHKeyDir         = 'C:\LabSources\SSHKeys'
        SSHPublicKey      = 'C:\LabSources\SSHKeys\id_ed25519.pub'
        SSHPrivateKey     = 'C:\LabSources\SSHKeys\id_ed25519'
        LabShareMount     = '/mnt/labshare'
        ProjectsRoot      = '/home/labadmin/projects'
        ShareName         = 'LabShare'
        SharePath         = 'C:\LabShare'
        GitRepoPath       = 'C:\LabShare\GitRepo'
    }

    # ── DHCP Scope (Linux leases) ──
    DHCP = @{
        ScopeId   = '10.0.10.0'
        Start     = '10.0.10.100'
        End       = '10.0.10.200'
        Mask      = '255.255.255.0'
    }

    # ── Role Menu (display order, consumed by Select-LabRoles) ──
    RoleMenu = @(
        @{ Tag = 'DC';         Label = 'Domain Controller (DC1) + DNS + CA'; Locked = $true  }
        @{ Tag = 'DSC';        Label = 'DSC Pull Server (DSC1)';             Locked = $false }
        @{ Tag = 'IIS';        Label = 'IIS Web Server (IIS1)';              Locked = $false }
        @{ Tag = 'SQL';        Label = 'SQL Server (SQL1)';                  Locked = $false }
        @{ Tag = 'WSUS';       Label = 'WSUS (WSUS1)';                        Locked = $false }
        @{ Tag = 'DHCP';       Label = 'DHCP Server (DHCP1)';                 Locked = $false }
        @{ Tag = 'FileServer'; Label = 'File Server (FILE1)';               Locked = $false }
        @{ Tag = 'PrintServer'; Label = 'Print Server (PRN1)';               Locked = $false }
        @{ Tag = 'Jumpbox';    Label = 'Jumpbox/Admin (JUMP1)';             Locked = $false }
        @{ Tag = 'Client';     Label = 'Client VM (WIN10-01)';              Locked = $false }
        @{ Separator = $true; Label = '── Linux VMs ──' }
        @{ Tag = 'Ubuntu'; Label = 'Ubuntu Server (LIN1)'; Locked = $false }
        @{ Tag = 'WebServerUbuntu'; Label = 'Web Server (Ubuntu/nginx)'; Default = $false }
        @{ Tag = 'DatabaseUbuntu';  Label = 'Database (Ubuntu/PostgreSQL)'; Default = $false }
        @{ Tag = 'DockerUbuntu';    Label = 'Docker (Ubuntu)'; Default = $false }
        @{ Tag = 'K8sUbuntu';       Label = 'Kubernetes (Ubuntu/k3s)'; Default = $false }
    )
}
