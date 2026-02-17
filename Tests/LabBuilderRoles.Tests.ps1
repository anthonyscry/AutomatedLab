Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:RolesDir = Join-Path $RepoRoot 'LabBuilder' 'Roles'

    # Mock AutomatedLab cmdlet before dot-sourcing role files
    function Get-LabMachineRoleDefinition { param($Role, $Properties) return @{ Role = $Role; Properties = $Properties } }

    # Dot-source all role files except DSCPullServer (Configuration keyword can't parse on Linux)
    $script:RoleFilesToSource = @(
        'DC.ps1', 'SQL.ps1', 'IIS.ps1', 'WSUS.ps1', 'DHCP.ps1',
        'FileServer.ps1', 'PrintServer.ps1', 'Jumpbox.ps1', 'Client.ps1'
    )
    foreach ($file in $script:RoleFilesToSource) {
        $filePath = Join-Path $script:RolesDir $file
        if (Test-Path $filePath) { . $filePath }
    }

    # Mock config for role function tests
    $script:MockConfig = @{
        VMNames = @{
            DC = 'DC1'; SQL = 'SQL1'; IIS = 'IIS1'; WSUS = 'WSUS1'
            DHCP = 'DHCP1'; FileServer = 'FILE1'; PrintServer = 'PRN1'
            DSC = 'DSC1'; Jumpbox = 'JUMP1'; Client = 'WIN10-01'
        }
        IPPlan = @{
            DC = '10.0.10.10'; SQL = '10.0.10.20'; IIS = '10.0.10.30'
            WSUS = '10.0.10.31'; DHCP = '10.0.10.32'; FileServer = '10.0.10.33'
            PrintServer = '10.0.10.34'; DSC = '10.0.10.40'; Jumpbox = '10.0.10.50'
            Client = '10.0.10.60'
        }
        Network = @{ Gateway = '10.0.10.1'; SwitchName = 'LabSwitch' }
        ServerOS = 'Windows Server 2022 Datacenter'
        ClientOS = 'Windows 11 Enterprise'
        ServerVM = @{ Memory = 2GB; MinMemory = 512MB; MaxMemory = 4GB; Processors = 2 }
        ClientVM = @{ Memory = 2GB; MinMemory = 512MB; MaxMemory = 4GB; Processors = 2 }
        DomainName = 'lab.local'
        CredentialUser = 'admin'
        SQL = @{ InstanceName = 'MSSQLSERVER'; Features = 'SQLENGINE'; SaPassword = 'Test123!'; Collation = '' }
        DSCPullServer = @{
            PullPort = 8080; CompliancePort = 9080
            RegistrationKeyDir = 'C:\DscService'; RegistrationKeyFile = 'RegistrationKey.txt'
        }
        DHCP = @{ ScopeId = '10.0.10.0'; Start = '10.0.10.100'; End = '10.0.10.200'; Mask = '255.255.255.0' }
        SelectedRoles = @('DC', 'FileServer', 'Client')
    }
}

Describe 'Role Script Syntax Validation' {
    It 'parses <File> without syntax errors' -ForEach @(
        @{ File = 'DC.ps1' }
        @{ File = 'SQL.ps1' }
        @{ File = 'IIS.ps1' }
        @{ File = 'WSUS.ps1' }
        @{ File = 'DHCP.ps1' }
        @{ File = 'FileServer.ps1' }
        @{ File = 'PrintServer.ps1' }
        @{ File = 'Jumpbox.ps1' }
        @{ File = 'Client.ps1' }
    ) {
        $filePath = Join-Path $script:RolesDir $File
        $filePath | Should -Exist

        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        # Filter out DSC Configuration parse errors (only fail on Linux, not real syntax errors)
        $realErrors = @($errors | Where-Object { $_.Message -notmatch 'DSC schema store' -and $_.Message -notmatch 'DSC for Linux' })
        $realErrors.Count | Should -Be 0 -Because "File $File should have no parse errors"
    }

    # DSCPullServer.ps1 uses the Configuration keyword which can't parse on Linux
    It 'DSCPullServer.ps1 exists and has valid PowerShell structure' {
        $filePath = Join-Path $script:RolesDir 'DSCPullServer.ps1'
        $filePath | Should -Exist
        $content = Get-Content $filePath -Raw
        $content | Should -Match 'function Get-LabRole_DSC'
        $content | Should -Match '\[CmdletBinding\(\)\]'
        $content | Should -Match '\[hashtable\]\$Config'
    }
}

Describe 'No Invalid Param Syntax (Regression Prevention)' {
    It '<File> does not contain param with dotted property syntax' -ForEach @(
        @{ File = 'DC.ps1' }
        @{ File = 'SQL.ps1' }
        @{ File = 'IIS.ps1' }
        @{ File = 'WSUS.ps1' }
        @{ File = 'DHCP.ps1' }
        @{ File = 'FileServer.ps1' }
        @{ File = 'PrintServer.ps1' }
        @{ File = 'DSCPullServer.ps1' }
        @{ File = 'Jumpbox.ps1' }
        @{ File = 'Client.ps1' }
    ) {
        $filePath = Join-Path $script:RolesDir $File
        $content = Get-Content $filePath -Raw
        # Match param($Variable.Property) pattern — invalid in PowerShell param blocks
        $content | Should -Not -Match 'param\(\$\w+\.\w+' -Because "ScriptBlock params must use simple variable names, not dotted properties"
    }
}

Describe 'Function Structure Validation' {
    It '<Function> exists and has CmdletBinding' -ForEach @(
        @{ File = 'DC.ps1';         Function = 'Get-LabRole_DC' }
        @{ File = 'SQL.ps1';        Function = 'Get-LabRole_SQL' }
        @{ File = 'IIS.ps1';        Function = 'Get-LabRole_IIS' }
        @{ File = 'WSUS.ps1';       Function = 'Get-LabRole_WSUS' }
        @{ File = 'DHCP.ps1';       Function = 'Get-LabRole_DHCP' }
        @{ File = 'FileServer.ps1'; Function = 'Get-LabRole_FileServer' }
        @{ File = 'PrintServer.ps1';Function = 'Get-LabRole_PrintServer' }
        @{ File = 'Jumpbox.ps1';    Function = 'Get-LabRole_Jumpbox' }
        @{ File = 'Client.ps1';     Function = 'Get-LabRole_Client' }
    ) {
        $cmd = Get-Command $Function -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty -Because "$Function should be defined"

        # Check for CmdletBinding via content
        $content = Get-Content (Join-Path $script:RolesDir $File) -Raw
        $content | Should -Match '\[CmdletBinding\(\)\]'
        $content | Should -Match '\[hashtable\]\$Config'
    }
}

Describe 'Role Definition Structure' {
    It '<Tag> role returns required keys' -ForEach @(
        @{ Function = 'Get-LabRole_DC';          Tag = 'DC' }
        @{ Function = 'Get-LabRole_SQL';         Tag = 'SQL' }
        @{ Function = 'Get-LabRole_IIS';         Tag = 'IIS' }
        @{ Function = 'Get-LabRole_WSUS';        Tag = 'WSUS' }
        @{ Function = 'Get-LabRole_DHCP';        Tag = 'DHCP' }
        @{ Function = 'Get-LabRole_FileServer';  Tag = 'FileServer' }
        @{ Function = 'Get-LabRole_PrintServer'; Tag = 'PrintServer' }
        @{ Function = 'Get-LabRole_Jumpbox';     Tag = 'Jumpbox' }
        @{ Function = 'Get-LabRole_Client';      Tag = 'Client' }
    ) {
        $result = & $Function -Config $script:MockConfig
        $result | Should -Not -BeNullOrEmpty

        $result.Tag        | Should -Be $Tag
        $result.VMName     | Should -Not -BeNullOrEmpty
        $result.OS         | Should -Not -BeNullOrEmpty
        $result.IP         | Should -Not -BeNullOrEmpty
        $result.Gateway    | Should -Not -BeNullOrEmpty
        $result.DnsServer1 | Should -Not -BeNullOrEmpty
        $result.PostInstall | Should -Not -BeNullOrEmpty -Because "Every role must have a PostInstall scriptblock"
    }
}

Describe 'DHCP Prerequisite Validation' {
    It 'returns early with warning when DHCP config section is missing' {
        $configNoDhcp = @{
            VMNames = $script:MockConfig.VMNames
            IPPlan = $script:MockConfig.IPPlan
            Network = $script:MockConfig.Network
            DomainName = 'lab.local'
        }

        $roleDef = Get-LabRole_DHCP -Config $configNoDhcp
        $postInstall = $roleDef.PostInstall

        # Execute PostInstall — capture warning stream (stream 3)
        $warningOutput = $postInstall.Invoke($configNoDhcp) 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        $warningOutput | Should -Not -BeNullOrEmpty -Because "Missing DHCP config should produce a warning"
        ($warningOutput | ForEach-Object { $_.Message }) -join ' ' | Should -Match 'DHCP' -Because "Warning should mention DHCP"
    }

    It 'returns early with warning when DHCP config keys are incomplete' {
        $configBadDhcp = @{
            VMNames = $script:MockConfig.VMNames
            IPPlan = $script:MockConfig.IPPlan
            Network = $script:MockConfig.Network
            DomainName = 'lab.local'
            DHCP = @{ ScopeId = '10.0.10.0' }  # Missing Start, End, Mask
        }

        $roleDef = Get-LabRole_DHCP -Config $configBadDhcp
        $warningOutput = $roleDef.PostInstall.Invoke($configBadDhcp) 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }

        $warningOutput | Should -Not -BeNullOrEmpty -Because "Incomplete DHCP config should produce a warning"
        ($warningOutput | ForEach-Object { $_.Message }) -join ' ' | Should -Match 'Start|End|Mask' -Because "Warning should mention missing keys"
    }
}

Describe 'DSC Prerequisite Validation' {
    # DSCPullServer.ps1 can't be dot-sourced on Linux due to Configuration keyword.
    # Instead, extract and test just the prerequisite validation logic by reading file content.
    It 'DSCPullServer.ps1 contains prerequisite validation' {
        $filePath = Join-Path $script:RolesDir 'DSCPullServer.ps1'
        $content = Get-Content $filePath -Raw
        $content | Should -Match 'prereq check failed' -Because "DSCPullServer should validate prerequisites"
        $content | Should -Match 'PullPort.*CompliancePort|CompliancePort.*PullPort' -Because "DSCPullServer should check for required config keys"
        $content | Should -Match 'RegistrationKeyDir' -Because "DSCPullServer should check for RegistrationKeyDir"
    }

    It 'DSCPullServer.ps1 returns early on missing config' {
        $filePath = Join-Path $script:RolesDir 'DSCPullServer.ps1'
        $content = Get-Content $filePath -Raw
        # Verify the prereq block has a return statement after the warning
        $content | Should -Match 'Write-Warning.*DSC.*prereq[\s\S]{0,200}return' -Because "DSCPullServer should return early when prereqs fail"
    }
}
