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
        FileServer = '10.0.10.80'
        Jumpbox    = '10.0.10.90'
        Client     = '10.0.10.100'
    }

    # ── VM Names (keyed by role tag) ──
    VMNames = @{
        DC         = 'DC1'
        DSC        = 'DSC1'
        IIS        = 'IIS1'
        SQL        = 'SQL1'
        WSUS       = 'WSUS1'
        FileServer = 'FILE1'
        Jumpbox    = 'JUMP1'
        Client     = 'WIN10-01'
    }

    # ── OS Images ──
    ServerOS = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
    ClientOS = 'Windows 11 Enterprise Evaluation'

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

    # ── AutomatedLab Timeout Overrides (minutes) ──
    Timeouts = @{
        DcRestart = 90
        AdwsReady = 120
        StartVM   = 90
        WaitVM    = 90
    }

    # ── Credentials ──
    CredentialEnvVar = 'LAB_ADMIN_PASSWORD'
    CredentialUser   = 'Administrator'

    # ── Required ISOs ──
    RequiredISOs = @('server2019.iso', 'windows11.iso')

    # ── DSC Pull Server Settings ──
    DSCPullServer = @{
        PullPort            = 8080
        CompliancePort      = 9080
        RegistrationKeyDir  = 'C:\DscPull\RegistrationKeys'
        RegistrationKeyFile = 'RegistrationKey.txt'
        ModulePath          = 'C:\Program Files\WindowsPowerShell\DscService\Modules'
        ConfigurationPath   = 'C:\Program Files\WindowsPowerShell\DscService\Configuration'
    }

    # ── Role Menu (display order, consumed by Select-LabRoles) ──
    RoleMenu = @(
        @{ Tag = 'DC';         Label = 'Domain Controller (DC1) + DNS + CA'; Locked = $true  }
        @{ Tag = 'DSC';        Label = 'DSC Pull Server (DSC1)';             Locked = $false }
        @{ Tag = 'IIS';        Label = 'IIS Web Server (IIS1)';              Locked = $false }
        @{ Tag = 'SQL';        Label = 'SQL Server (SQL1) [scaffold]';       Locked = $false }
        @{ Tag = 'WSUS';       Label = 'WSUS (WSUS1) [scaffold]';           Locked = $false }
        @{ Tag = 'FileServer'; Label = 'File Server (FILE1)';               Locked = $false }
        @{ Tag = 'Jumpbox';    Label = 'Jumpbox/Admin (JUMP1)';             Locked = $false }
        @{ Tag = 'Client';     Label = 'Client VM (WIN10-01)';              Locked = $false }
    )
}
