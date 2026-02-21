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

        # Multi-switch definitions for complex networking.
        # Each entry defines a named vSwitch with its own subnet.
        # When Switches is present, Get-LabNetworkConfig uses these instead of the
        # flat SwitchName/AddressSpace above. The flat keys remain for backward compat.
        Switches = @(
            @{
                Name         = 'LabCorpNet'
                AddressSpace = '10.0.10.0/24'
                GatewayIp    = '10.0.10.1'
                NatName      = 'LabCorpNetNAT'
            }
            @{
                Name         = 'LabDMZ'
                AddressSpace = '10.0.20.0/24'
                GatewayIp    = '10.0.20.1'
                NatName      = 'LabDMZNAT'
            }
        )

        # Routing configuration for inter-subnet communication.
        # Mode 'host'   = add static routes on the Hyper-V host between subnets.
        # Mode 'gateway'= use a gateway VM that forwards between subnets.
        Routing = @{
            # Mode: 'host' or 'gateway'
            Mode = 'host'
            # GatewayVM: VM name acting as router (only used when Mode = 'gateway')
            GatewayVM = ''
            # EnableForwarding: enable IP forwarding on the gateway VM (Mode = 'gateway')
            EnableForwarding = $true
        }
    }

    IPPlan = @{
        # Changing these IPs remaps static addressing for core VMs.
        # New format: hashtable with IP, Switch, and optional VlanId.
        # Backward compat: plain string = default/first switch, no VLAN.
        DC1  = @{ IP = '10.0.10.10'; Switch = 'LabCorpNet' }
        SVR1 = @{ IP = '10.0.10.20'; Switch = 'LabCorpNet'; VlanId = 100 }
        WS1  = @{ IP = '10.0.20.30'; Switch = 'LabDMZ'; VlanId = 200 }
        DSC1 = '10.0.10.40'   # backward compat: plain string = default switch, no VLAN
        LIN1 = @{ IP = '10.0.10.110'; Switch = 'LabCorpNet' }
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

    TTL = @{
        # Changing Enabled toggles whether lab TTL monitoring is active.
        Enabled = $false
        # Changing IdleMinutes sets how long all VMs must be idle before TTL fires (0 = disabled).
        IdleMinutes = 0
        # Changing WallClockHours sets maximum lab runtime before TTL fires.
        WallClockHours = 8
        # Changing Action sets what happens when TTL expires: 'Suspend' (Save-VM) or 'Off' (Stop-VM).
        Action = 'Suspend'
    }

    STIG = @{
        # Changing Enabled toggles whether DISA STIG DSC baselines are applied during PostInstall.
        Enabled = $false
        # Changing AutoApplyOnDeploy toggles whether STIGs apply automatically during deployment.
        AutoApplyOnDeploy = $true
        # Changing ComplianceCachePath moves where STIG compliance results are cached.
        ComplianceCachePath = '.planning/stig-compliance.json'
        # Changing Exceptions adds per-VM STIG rule exclusions (V-numbers skipped at compile time).
        # Example: Exceptions = @{ 'dc1' = @('V-12345', 'V-67890'); 'svr1' = @('V-11111') }
        Exceptions = @{}
    }

    ADMX = @{
        # Changing Enabled toggles whether ADMX Central Store is populated after DC promotion.
        Enabled = $true
        # Changing CreateBaselineGPO toggles whether baseline GPOs are created from JSON templates.
        CreateBaselineGPO = $false
        # Changing ThirdPartyADMX adds custom ADMX bundles to import (operator-provided local paths).
        # Example: ThirdPartyADMX = @(@{ Name = 'Chrome'; Path = 'C:\ADMX\Chrome' })
        ThirdPartyADMX = @()
    }

    Dashboard = @{
        # Changing SnapshotStaleDays sets the warning threshold for snapshot age (in days).
        SnapshotStaleDays = 7
        # Changing SnapshotStaleCritical sets the critical threshold for snapshot age (in days).
        SnapshotStaleCritical = 30
        # Changing DiskUsagePercent sets the warning threshold for VHDx usage (in percent).
        DiskUsagePercent = 80
        # Changing DiskUsageCritical sets the critical threshold for VHDx usage (in percent).
        DiskUsageCritical = 95
        # Changing UptimeStaleHours sets the stale threshold for VM uptime (in hours).
        UptimeStaleHours = 72
    }

    Analytics = @{
        # Changing Enabled toggles whether lab analytics events are tracked.
        Enabled = $true
        # Changing StoragePath moves where analytics events are stored.
        StoragePath = '.planning/analytics.json'
        # Changing RetentionDays sets how long to keep analytics events (0 = keep forever).
        RetentionDays = 90
    }

    Performance = @{
        # Changing Enabled toggles whether performance metrics are collected.
        Enabled = $true
        # Changing StoragePath moves where performance metrics are stored.
        StoragePath = '.planning/performance-metrics.json'
        # Changing RetentionDays sets how long to keep performance metrics (0 = keep forever).
        RetentionDays = 90
    }

    Reports = @{
        # Changing ComplianceReportPath sets where compliance reports are saved.
        ComplianceReportPath = '.planning/reports/compliance'
        # Changing IncludeDetailedResults toggles verbose rule-level details in reports.
        IncludeDetailedResults = $false
        # Changing ComplianceThresholdPercent sets the warning threshold for compliance rate.
        ComplianceThresholdPercent = 80
        # Changing ReportFormats sets default output formats for compliance reports.
        # Valid values: 'Console', 'Html', 'Csv', 'Json'
        ReportFormats = @('Console', 'Html')
    }

    ReportSchedule = @{
        # Changing Enabled toggles whether scheduled reports can be created.
        Enabled = $true
        # Changing TaskPrefix sets the prefix for scheduled report task names.
        TaskPrefix = 'AutomatedLabReport'
        # Changing OutputBasePath sets the base directory where scheduled reports are saved.
        OutputBasePath = '.planning/reports/scheduled'
    }

    Workflows = @{
        # Changing StoragePath moves where workflow definitions are stored.
        StoragePath = '.planning/workflows'
        # Changing Enabled toggles whether custom workflows can be executed.
        Enabled = $true
    }

    SSH = @{
        # Changing KnownHostsPath moves where lab SSH host keys are stored.
        # This file is cleared on teardown so redeploy gets fresh keys.
        KnownHostsPath = 'C:\LabSources\SSHKeys\lab_known_hosts'
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
            CentOS = '10.0.10.115'
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
            CentOS = 'LINCENT1'
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
            CentOS9 = @{
                DisplayName = 'CentOS Stream 9'
                ISOPattern  = 'CentOS-Stream-9*.iso'
                CloudInit   = 'nocloud'
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
            # SSH retry settings for Invoke-LinuxRolePostInstall
            SSHRetryCount = 3
            SSHRetryDelaySeconds = 10
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
            @{ Tag = 'CentOS'; Label = 'CentOS Stream (LINCENT1)'; Locked = $false }
            @{ Tag = 'WebServerUbuntu'; Label = 'Web Server (Ubuntu/nginx)'; Default = $false }
            @{ Tag = 'DatabaseUbuntu'; Label = 'Database (Ubuntu/PostgreSQL)'; Default = $false }
            @{ Tag = 'DockerUbuntu'; Label = 'Docker (Ubuntu)'; Default = $false }
            @{ Tag = 'K8sUbuntu'; Label = 'Kubernetes (Ubuntu/k3s)'; Default = $false }
        )
    }
}

# Expose Builder config for LabBuilder scripts (intentional coupling -- see 01-RESEARCH.md)
$LabBuilderConfig = $GlobalLabConfig.Builder

# ── Configuration Validation ──────────────────────────────────────────────
# Validates required fields exist and have valid values.
# Fails loudly per design: missing required fields = script stops.

function Test-LabConfigRequired {
    [CmdletBinding()]
    param([hashtable]$Config)

    $requiredFields = @{
        'Lab.Name'              = { param($v) $v -match '^[a-zA-Z0-9_-]+$' }
        'Lab.DomainName'        = { param($v) $v -match '^[a-z0-9.-]+$' }
        'Network.SwitchName'    = { param($v) $v -match '^[a-zA-Z0-9_ -]+$' }
        'Network.AddressSpace'  = { param($v) $v -match '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$' }
        'Network.GatewayIp'     = { param($v) $v -match '^\d{1,3}(\.\d{1,3}){3}$' }
        'Network.DnsIp'         = { param($v) $v -match '^\d{1,3}(\.\d{1,3}){3}$' }
        'Credentials.InstallUser' = { param($v) -not [string]::IsNullOrWhiteSpace($v) }
        'Credentials.AdminPassword' = { param($v) -not [string]::IsNullOrWhiteSpace($v) }
        'Paths.LabRoot'         = { param($v) -not [string]::IsNullOrWhiteSpace($v) }
        'Paths.LabSourcesRoot'  = { param($v) -not [string]::IsNullOrWhiteSpace($v) }
    }

    foreach ($keyPath in $requiredFields.Keys) {
        $parts = $keyPath -split '\.'
        $value = $Config
        foreach ($part in $parts) {
            if (-not ($value -is [hashtable]) -or -not $value.ContainsKey($part)) {
                throw "Lab-Config validation failed: Required field '$keyPath' is missing from `$GlobalLabConfig."
            }
            $value = $value[$part]
        }
        if (-not (& $requiredFields[$keyPath] $value)) {
            throw "Lab-Config validation failed: Invalid value for '$keyPath': '$value'"
        }
    }

    # Validate Switches array entries if present
    if ($Config.ContainsKey('Network') -and $Config.Network.ContainsKey('Switches') -and $null -ne $Config.Network.Switches) {
        $switchIndex = 0
        foreach ($sw in $Config.Network.Switches) {
            if (-not ($sw -is [hashtable])) {
                throw "Lab-Config validation failed: Network.Switches[$switchIndex] must be a hashtable."
            }
            if (-not $sw.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace($sw['Name'])) {
                throw "Lab-Config validation failed: Network.Switches[$switchIndex] is missing required key 'Name'."
            }
            if (-not $sw.ContainsKey('AddressSpace') -or [string]::IsNullOrWhiteSpace($sw['AddressSpace'])) {
                throw "Lab-Config validation failed: Network.Switches[$switchIndex] is missing required key 'AddressSpace'."
            }
            $switchIndex++
        }
    }
}

Test-LabConfigRequired -Config $GlobalLabConfig

if ($GlobalLabConfig.Credentials.AdminPassword -eq 'SimpleLab123!') {
    Write-Warning "[Lab-Config] AdminPassword is set to the default value. Set the '$($GlobalLabConfig.Credentials.PasswordEnvVar)' environment variable or update Lab-Config.ps1 for production use."
}
