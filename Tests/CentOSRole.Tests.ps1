# CentOSRole.Tests.ps1 -- Pester 5 tests for Get-LabRole_CentOS definition

BeforeAll {
    Set-StrictMode -Version Latest
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:rolesDir = Join-Path (Join-Path $script:repoRoot 'LabBuilder') 'Roles'
    $script:centOSPath = Join-Path $script:rolesDir 'CentOS.ps1'
    $script:ubuntuPath = Join-Path $script:rolesDir 'Ubuntu.ps1'
    $script:linuxRoleBasePath = Join-Path $script:rolesDir 'LinuxRoleBase.ps1'

    # Stub Hyper-V cmdlets and Linux functions before dot-sourcing
    if (-not (Get-Command Get-VMNetworkAdapter -ErrorAction SilentlyContinue)) {
        function Get-VMNetworkAdapter { param($VMName, $ErrorAction) [PSCustomObject]@{ IPAddresses = @('10.0.10.115') } }
    }
    if (-not (Get-Command Start-VM -ErrorAction SilentlyContinue)) {
        function Start-VM { param($Name) }
    }
    if (-not (Get-Command New-LinuxVM -ErrorAction SilentlyContinue)) {
        function New-LinuxVM { param([string]$UbuntuIsoPath, [string]$CidataVhdxPath, [string]$VMName, [string]$SwitchName, $Memory, $MinMemory, $MaxMemory, $Processors) }
    }
    if (-not (Get-Command New-CidataVhdx -ErrorAction SilentlyContinue)) {
        function New-CidataVhdx { param($OutputPath, $Hostname, $Username, $PasswordHash, $SSHPublicKey) }
    }
    if (-not (Get-Command Get-Sha512PasswordHash -ErrorAction SilentlyContinue)) {
        function Get-Sha512PasswordHash { param($Password) return '$6$salt$hash' }
    }
    if (-not (Get-Command Finalize-LinuxInstallMedia -ErrorAction SilentlyContinue)) {
        function Finalize-LinuxInstallMedia { param($VMName) }
    }
    if (-not (Get-Command Invoke-LinuxRoleCreateVM -ErrorAction SilentlyContinue)) {
        function Invoke-LinuxRoleCreateVM { param([hashtable]$LabConfig, [string]$VMNameKey, [string]$ISOPattern) }
    }
    if (-not (Get-Command Invoke-LinuxRolePostInstall -ErrorAction SilentlyContinue)) {
        function Invoke-LinuxRolePostInstall { param([hashtable]$LabConfig, [string]$VMNameKey, [string]$BashScript, [string]$SuccessMessage, [int]$RetryCount, [int]$RetryDelaySeconds) }
    }

    # Provide $GlobalLabConfig
    $script:GlobalLabConfig = @{
        SSH = @{ KnownHostsPath = 'C:\LabSources\SSHKeys\lab_known_hosts' }
    }
    $GlobalLabConfig = $script:GlobalLabConfig

    # Dot-source CentOS role (and Ubuntu for structure comparison)
    . $script:centOSPath
    . $script:ubuntuPath

    # Standard mock config used across tests
    $script:MockConfig = @{
        VMNames    = @{ CentOS = 'LINCENT1'; Ubuntu = 'LIN1' }
        IPPlan     = @{ CentOS = '10.0.10.115'; DC = '10.0.10.10'; Ubuntu = '10.0.10.110' }
        Network    = @{ SwitchName = 'LabBuilder'; Gateway = '10.0.10.1' }
        DomainName = 'simplelab.local'
        LinuxVM    = @{ Memory = 2GB; MinMemory = 1GB; MaxMemory = 4GB; Processors = 2 }
        LinuxOS    = 'Ubuntu 24.04 LTS'
    }
}

Describe 'Get-LabRole_CentOS - Role definition structure' {

    BeforeEach {
        Mock Write-Warning { }
        Mock Test-Path { $false }  # Suppress Lab-Common.ps1 / LinuxRoleBase.ps1 dot-source
    }

    It 'returns a hashtable' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role | Should -BeOfType [hashtable]
    }

    It 'has Tag set to CentOS' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.Tag | Should -Be 'CentOS'
    }

    It 'has IsLinux set to true' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.IsLinux | Should -Be $true
    }

    It 'has SkipInstallLab set to true' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.SkipInstallLab | Should -Be $true
    }

    It 'returns correct VMName from Config.VMNames.CentOS' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.VMName | Should -Be 'LINCENT1'
    }

    It 'returns correct IP from Config.IPPlan.CentOS' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.IP | Should -Be '10.0.10.115'
    }

    It 'has OS set to CentOS Stream 9' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.OS | Should -Be 'CentOS Stream 9'
    }

    It 'has Roles as an empty collection' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        # @() in a hashtable may return $null or empty array depending on PS version
        if ($null -ne $role.Roles) {
            @($role.Roles).Count | Should -Be 0
        }
        else {
            # $null is acceptable for an empty roles collection
            $role.Roles | Should -BeNullOrEmpty
        }
    }

    It 'has CreateVM scriptblock' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.CreateVM | Should -BeOfType [scriptblock]
    }

    It 'has PostInstall scriptblock' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.PostInstall | Should -BeOfType [scriptblock]
    }
}

Describe 'Get-LabRole_CentOS - CreateVM scriptblock' {

    BeforeEach {
        Mock Write-Warning { }
        Mock Test-Path { $false }
    }

    It 'CreateVM scriptblock references CentOS-Stream-9*.iso pattern' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.CreateVM.ToString() | Should -Match 'CentOS-Stream-9\*\.iso'
    }

    It 'CreateVM scriptblock calls Invoke-LinuxRoleCreateVM' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.CreateVM.ToString() | Should -Match 'Invoke-LinuxRoleCreateVM'
    }

    It 'CreateVM scriptblock uses VMNameKey CentOS' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.CreateVM.ToString() | Should -Match "'CentOS'"
    }
}

Describe 'Get-LabRole_CentOS - PostInstall scriptblock' {

    BeforeEach {
        Mock Write-Warning { }
        Mock Test-Path { $false }
    }

    It 'PostInstall scriptblock uses dnf (not apt-get)' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.PostInstall.ToString() | Should -Match 'dnf'
    }

    It 'PostInstall scriptblock does NOT use apt-get' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.PostInstall.ToString() | Should -Not -Match 'apt-get'
    }

    It 'PostInstall scriptblock calls Invoke-LinuxRolePostInstall' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.PostInstall.ToString() | Should -Match 'Invoke-LinuxRolePostInstall'
    }

    It 'PostInstall scriptblock uses VMNameKey CentOS' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.PostInstall.ToString() | Should -Match "'CentOS'"
    }

    It 'PostInstall bash script enables sshd service (not ssh)' {
        $role = Get-LabRole_CentOS -Config $script:MockConfig
        $role.PostInstall.ToString() | Should -Match 'sshd'
    }
}

Describe 'Get-LabRole_CentOS - Null-guard behavior' {

    It 'returns empty role with warning when LinuxVM config missing' {
        $configNoLinux = @{
            VMNames    = @{ CentOS = 'LINCENT1' }
            IPPlan     = @{ CentOS = '10.0.10.115' }
            Network    = @{ SwitchName = 'LabBuilder'; Gateway = '10.0.10.1' }
            DomainName = 'simplelab.local'
        }

        $warnings = [System.Collections.Generic.List[string]]::new()
        Mock Write-Warning { param($Message) $warnings.Add($Message) }

        $role = Get-LabRole_CentOS -Config $configNoLinux

        $warnings | Should -Not -BeNullOrEmpty
        $warnings[0] | Should -Match 'Linux VM configuration not found'
    }

    It 'empty role from null-guard has Tag=CentOS' {
        $configNoLinux = @{
            VMNames    = @{ CentOS = 'LINCENT1' }
            IPPlan     = @{ CentOS = '10.0.10.115' }
            Network    = @{ SwitchName = 'LabBuilder'; Gateway = '10.0.10.1' }
            DomainName = 'simplelab.local'
        }

        Mock Write-Warning { }
        $role = Get-LabRole_CentOS -Config $configNoLinux
        $role.Tag | Should -Be 'CentOS'
    }

    It 'empty role from null-guard has IsLinux=true' {
        $configNoLinux = @{
            VMNames    = @{ CentOS = 'LINCENT1' }
            IPPlan     = @{ CentOS = '10.0.10.115' }
            Network    = @{ SwitchName = 'LabBuilder'; Gateway = '10.0.10.1' }
            DomainName = 'simplelab.local'
        }

        Mock Write-Warning { }
        $role = Get-LabRole_CentOS -Config $configNoLinux
        $role.IsLinux | Should -Be $true
    }

    It 'empty role from null-guard has SkipInstallLab=true' {
        $configNoLinux = @{
            VMNames    = @{ CentOS = 'LINCENT1' }
            IPPlan     = @{ CentOS = '10.0.10.115' }
            Network    = @{ SwitchName = 'LabBuilder'; Gateway = '10.0.10.1' }
            DomainName = 'simplelab.local'
        }

        Mock Write-Warning { }
        $role = Get-LabRole_CentOS -Config $configNoLinux
        $role.SkipInstallLab | Should -Be $true
    }
}

Describe 'Get-LabRole_CentOS - Structure parity with Ubuntu role' {

    BeforeEach {
        Mock Write-Warning { }
        Mock Test-Path { $false }
    }

    It 'CentOS role has same property names as Ubuntu role' {
        $ubuntuConfig = $script:MockConfig.Clone()
        $centosRole = Get-LabRole_CentOS -Config $script:MockConfig
        $ubuntuRole = Get-LabRole_Ubuntu -Config $ubuntuConfig

        $centosKeys = $centosRole.Keys | Sort-Object
        $ubuntuKeys = $ubuntuRole.Keys | Sort-Object

        # All Ubuntu keys should also exist in CentOS role
        foreach ($key in $ubuntuKeys) {
            $centosRole.ContainsKey($key) | Should -Be $true -Because "CentOS role should have property '$key' matching Ubuntu role"
        }
    }

    It 'CentOS and Ubuntu roles both have Tag, VMName, IsLinux, SkipInstallLab, CreateVM, PostInstall' {
        $centosRole = Get-LabRole_CentOS -Config $script:MockConfig
        $ubuntuRole = Get-LabRole_Ubuntu -Config $script:MockConfig

        $requiredKeys = @('Tag', 'VMName', 'IsLinux', 'SkipInstallLab', 'CreateVM', 'PostInstall', 'Roles', 'OS', 'IP', 'Gateway', 'DnsServer1')
        foreach ($key in $requiredKeys) {
            $centosRole.ContainsKey($key) | Should -Be $true -Because "CentOS role must have '$key'"
            $ubuntuRole.ContainsKey($key) | Should -Be $true -Because "Ubuntu role must have '$key'"
        }
    }
}

Describe 'CentOS.ps1 - File structure verification' {

    It 'CentOS.ps1 exists' {
        $script:centOSPath | Should -Exist
    }

    It 'CentOS.ps1 contains Get-LabRole_CentOS function' {
        $content = Get-Content -Raw -Path $script:centOSPath
        $content | Should -Match 'function Get-LabRole_CentOS'
    }

    It 'CentOS.ps1 has no syntax errors' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:centOSPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0 -Because 'CentOS.ps1 should have no parse errors'
    }

    It 'CentOS.ps1 uses CentOS-Stream-9*.iso pattern' {
        $content = Get-Content -Raw -Path $script:centOSPath
        $content | Should -Match 'CentOS-Stream-9\*\.iso'
    }

    It 'CentOS.ps1 uses dnf package manager' {
        $content = Get-Content -Raw -Path $script:centOSPath
        $content | Should -Match '\bdnf\b'
    }

    It 'CentOS.ps1 references LinuxRoleBase.ps1' {
        $content = Get-Content -Raw -Path $script:centOSPath
        $content | Should -Match 'LinuxRoleBase\.ps1'
    }
}

Describe 'Lab-Config.ps1 - CentOS entries' {

    BeforeAll {
        $script:labConfigPath = Join-Path $script:repoRoot 'Lab-Config.ps1'
        $script:labConfigContent = Get-Content -Raw -Path $script:labConfigPath
    }

    It 'Lab-Config.ps1 contains CentOS in VMNames' {
        $script:labConfigContent | Should -Match "CentOS\s*=\s*'LINCENT1'"
    }

    It 'Lab-Config.ps1 contains CentOS in IPPlan' {
        $script:labConfigContent | Should -Match "CentOS\s*=\s*'10\.0\.10\.115'"
    }

    It 'Lab-Config.ps1 contains CentOS in RoleMenu' {
        $script:labConfigContent | Should -Match "Tag\s*=\s*'CentOS'"
    }

    It 'Lab-Config.ps1 RoleMenu has CentOS Stream label' {
        $script:labConfigContent | Should -Match 'CentOS Stream'
    }

    It 'Lab-Config.ps1 contains CentOS9 in SupportedDistros' {
        $script:labConfigContent | Should -Match 'CentOS9'
    }

    It 'Lab-Config.ps1 CentOS9 SupportedDistros entry has nocloud CloudInit' {
        $script:labConfigContent | Should -Match "CloudInit\s*=\s*'nocloud'"
    }

    It 'Lab-Config.ps1 CentOS9 SupportedDistros entry has correct ISOPattern' {
        $script:labConfigContent | Should -Match 'CentOS-Stream-9\*\.iso'
    }
}
