# ComplexNetworking-MultiSwitch.Tests.ps1
# Tests for multi-switch config, creation, NAT, and pairwise subnet conflict detection.
# Phase 23, Plan 01 -- Complex Networking

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    . (Join-Path $script:repoRoot 'Private' 'Get-LabNetworkConfig.ps1')
    . (Join-Path $script:repoRoot 'Public' 'New-LabSwitch.ps1')
    . (Join-Path $script:repoRoot 'Public' 'New-LabNAT.ps1')
    . (Join-Path $script:repoRoot 'Private' 'Test-LabVirtualSwitchSubnetConflict.ps1')

    # Stub dependencies not under test
    if (-not (Get-Command Get-LabConfig -ErrorAction SilentlyContinue)) {
        function Get-LabConfig { $null }
    }
    if (-not (Get-Command Write-LabStatus -ErrorAction SilentlyContinue)) {
        function Write-LabStatus { param($Status, $Message, $Indent) }
    }
    if (-not (Get-Command Test-LabNetwork -ErrorAction SilentlyContinue)) {
        function Test-LabNetwork { [PSCustomObject]@{ Exists = $false; SwitchName = 'SimpleLab'; SwitchType = '' } }
    }

    # Stub Hyper-V cmdlets that don't exist in non-Hyper-V environments (WSL/CI).
    # Pester requires a command to exist before it can be mocked.
    # These stubs are overridden by Mock in each Describe's BeforeEach.
    if (-not (Get-Command Get-VMSwitch -ErrorAction SilentlyContinue)) {
        function Get-VMSwitch { param($Name) @() }
    }
    if (-not (Get-Command New-VMSwitch -ErrorAction SilentlyContinue)) {
        function New-VMSwitch { param($Name, $SwitchType) [PSCustomObject]@{ Name = $Name; SwitchType = $SwitchType } }
    }
    if (-not (Get-Command Remove-VMSwitch -ErrorAction SilentlyContinue)) {
        function Remove-VMSwitch { param($Name, [switch]$Force) }
    }
    if (-not (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue)) {
        function Get-NetIPAddress { param($InterfaceAlias, $AddressFamily) @() }
    }
    if (-not (Get-Command New-NetIPAddress -ErrorAction SilentlyContinue)) {
        function New-NetIPAddress { param($InterfaceAlias, $IPAddress, $PrefixLength) }
    }
    if (-not (Get-Command Remove-NetIPAddress -ErrorAction SilentlyContinue)) {
        function Remove-NetIPAddress { param($InterfaceAlias, $IPAddress, [switch]$Confirm) }
    }
    if (-not (Get-Command Get-NetNat -ErrorAction SilentlyContinue)) {
        function Get-NetNat { param($Name) @() }
    }
    if (-not (Get-Command New-NetNat -ErrorAction SilentlyContinue)) {
        function New-NetNat { param($Name, $InternalIPInterfaceAddressPrefix) [PSCustomObject]@{ Name = $Name; InternalIPInterfaceAddressPrefix = $InternalIPInterfaceAddressPrefix } }
    }
    if (-not (Get-Command Remove-NetNat -ErrorAction SilentlyContinue)) {
        function Remove-NetNat { param($Name, [switch]$Confirm) }
    }
    if (-not (Get-Command Get-Module -ErrorAction SilentlyContinue)) {
        # Get-Module always exists but may not return Hyper-V
        # no stub needed
    }
}

# --- Get-LabNetworkConfig multi-switch support --------------------------------

Describe 'Get-LabNetworkConfig - Switches array' {

    Context 'when GlobalLabConfig has a Switches array' {
        BeforeEach {
            # Set up GlobalLabConfig with Switches
            $global:GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'AutomatedLab'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'AutomatedLabNAT'
                    DnsIp        = '10.0.10.10'
                    Switches     = @(
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
                }
            }
            Mock Get-LabConfig { $null }
        }

        AfterEach {
            Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
        }

        It 'returns a Switches property on the result object' {
            $result = Get-LabNetworkConfig
            $result.PSObject.Properties.Name | Should -Contain 'Switches'
        }

        It 'returns the correct count of switches from GlobalLabConfig' {
            $result = Get-LabNetworkConfig
            $result.Switches.Count | Should -Be 2
        }

        It 'returns switches normalized as PSCustomObject with Name property' {
            $result = Get-LabNetworkConfig
            $result.Switches[0] | Should -BeOfType [PSCustomObject]
            $result.Switches[0].Name | Should -Be 'LabCorpNet'
        }

        It 'preserves AddressSpace on each switch' {
            $result = Get-LabNetworkConfig
            $result.Switches[1].AddressSpace | Should -Be '10.0.20.0/24'
        }

        It 'preserves GatewayIp on each switch' {
            $result = Get-LabNetworkConfig
            $result.Switches[0].GatewayIp | Should -Be '10.0.10.1'
        }

        It 'preserves NatName when provided' {
            $result = Get-LabNetworkConfig
            $result.Switches[0].NatName | Should -Be 'LabCorpNetNAT'
        }

        It 'still returns flat properties (Gateway, Subnet) for backward compat' {
            $result = Get-LabNetworkConfig
            $result.PSObject.Properties.Name | Should -Contain 'Gateway'
            $result.PSObject.Properties.Name | Should -Contain 'Subnet'
        }
    }

    Context 'when GlobalLabConfig has no Switches array (single-switch backward compat)' {
        BeforeEach {
            $global:GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'AutomatedLab'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'AutomatedLabNAT'
                    DnsIp        = '10.0.10.10'
                }
            }
            Mock Get-LabConfig { $null }
        }

        AfterEach {
            Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
        }

        It 'returns a Switches property with exactly 1 entry' {
            $result = Get-LabNetworkConfig
            $result.PSObject.Properties.Name | Should -Contain 'Switches'
            $result.Switches.Count | Should -Be 1
        }

        It 'builds the single-switch entry from flat SwitchName/AddressSpace' {
            $result = Get-LabNetworkConfig
            $result.Switches[0].Name | Should -Be 'AutomatedLab'
            $result.Switches[0].AddressSpace | Should -Be '10.0.10.0/24'
        }

        It 'uses NatName from flat config for the single-switch entry' {
            $result = Get-LabNetworkConfig
            $result.Switches[0].NatName | Should -Be 'AutomatedLabNAT'
        }
    }

    Context 'NatName defaulting' {
        BeforeEach {
            $global:GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'AutomatedLab'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    DnsIp        = '10.0.10.10'
                    Switches     = @(
                        @{
                            Name         = 'LabFrontend'
                            AddressSpace = '10.0.30.0/24'
                            GatewayIp    = '10.0.30.1'
                            # NatName intentionally omitted
                        }
                    )
                }
            }
            Mock Get-LabConfig { $null }
        }

        AfterEach {
            Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
        }

        It 'defaults NatName to Name + NAT when not specified' {
            $result = Get-LabNetworkConfig
            $result.Switches[0].NatName | Should -Be 'LabFrontendNAT'
        }
    }

    Context 'when NetworkConfiguration.Switches is provided via Get-LabConfig' {
        BeforeEach {
            $mockConfig = [PSCustomObject]@{
                NetworkConfiguration = [PSCustomObject]@{
                    Switches = @(
                        [PSCustomObject]@{
                            Name         = 'ConfigSwitch1'
                            AddressSpace = '192.168.1.0/24'
                            GatewayIp    = '192.168.1.1'
                            NatName      = 'ConfigSwitch1NAT'
                        }
                    )
                }
            }
            Mock Get-LabConfig { $mockConfig }
        }

        It 'uses Switches from Get-LabConfig NetworkConfiguration when present' {
            $result = Get-LabNetworkConfig
            $result.Switches.Count | Should -Be 1
            $result.Switches[0].Name | Should -Be 'ConfigSwitch1'
        }
    }
}

# --- Lab-Config.ps1 Switches array validation ---------------------------------

Describe 'Lab-Config.ps1 Switches schema' {
    BeforeAll {
        # Read the actual Lab-Config.ps1 content to check for Switches
        $configPath = Join-Path $script:repoRoot 'Lab-Config.ps1'
        $configContent = Get-Content -Path $configPath -Raw -ErrorAction SilentlyContinue
        $script:configContent = $configContent
    }

    It 'Lab-Config.ps1 contains a Switches key in the Network block' {
        $script:configContent | Should -Match 'Switches\s*='
    }

    It 'Lab-Config.ps1 Switches array has at least 2 entries' {
        # Load the config and inspect GlobalLabConfig
        $tempFile = [System.IO.Path]::GetTempFileName() + '.ps1'
        try {
            Copy-Item -Path (Join-Path $script:repoRoot 'Lab-Config.ps1') -Destination $tempFile
            $lines = pwsh -NoProfile -NonInteractive -Command ". '$tempFile'; `$GlobalLabConfig.Network.Switches.Count" 2>/dev/null
            $countLine = @($lines) | Select-Object -Last 1
            [int]$countLine | Should -BeGreaterOrEqual 2
        } finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It 'each Switches entry has a Name key' {
        $tempFile = [System.IO.Path]::GetTempFileName() + '.ps1'
        try {
            Copy-Item -Path (Join-Path $script:repoRoot 'Lab-Config.ps1') -Destination $tempFile
            $lines = pwsh -NoProfile -NonInteractive -Command ". '$tempFile'; `$GlobalLabConfig.Network.Switches | ForEach-Object { `$_.ContainsKey('Name') } | Where-Object { -not `$_ } | Measure-Object | Select-Object -ExpandProperty Count" 2>/dev/null
            $countLine = @($lines) | Select-Object -Last 1
            [int]$countLine | Should -Be 0
        } finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }

    It 'each Switches entry has an AddressSpace key' {
        $tempFile = [System.IO.Path]::GetTempFileName() + '.ps1'
        try {
            Copy-Item -Path (Join-Path $script:repoRoot 'Lab-Config.ps1') -Destination $tempFile
            $lines = pwsh -NoProfile -NonInteractive -Command ". '$tempFile'; `$GlobalLabConfig.Network.Switches | ForEach-Object { `$_.ContainsKey('AddressSpace') } | Where-Object { -not `$_ } | Measure-Object | Select-Object -ExpandProperty Count" 2>/dev/null
            $countLine = @($lines) | Select-Object -Last 1
            [int]$countLine | Should -Be 0
        } finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

# --- New-LabSwitch multi-switch support ---------------------------------------

Describe 'New-LabSwitch - multi-switch' {

    BeforeEach {
        # Stub only what New-LabSwitch actually calls (avoids Register-HyperVMocks
        # which requires Hyper-V cmdlets to exist before mocking)
        Mock Get-Module {
            [PSCustomObject]@{ Name = 'Hyper-V'; Version = '2.0.0.0' }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }

        Mock Get-VMSwitch { @() }
        Mock New-VMSwitch { [PSCustomObject]@{ Name = $Name; SwitchType = 'Internal' } }
        Mock Remove-VMSwitch { }
        Mock Start-Sleep { }

        Mock Test-LabNetwork { [PSCustomObject]@{ Exists = $false; SwitchName = 'SimpleLab'; SwitchType = '' } }
        Mock Get-LabNetworkConfig {
            [PSCustomObject]@{
                Switches = @(
                    [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                    [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT' }
                )
                Subnet  = '10.0.10.0/24'
                Gateway = '10.0.10.1'
            }
        }
    }

    Context '-Switches parameter' {
        It 'creates a switch for each entry in -Switches array' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT' }
            )
            $results = New-LabSwitch -Switches $switches
            Should -Invoke New-VMSwitch -Times 2 -Exactly
        }

        It 'returns an array of result objects when -Switches is used' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT' }
            )
            $results = New-LabSwitch -Switches $switches
            $results.Count | Should -Be 2
        }

        It 'each result has SwitchName and Status properties' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
            )
            $results = New-LabSwitch -Switches $switches
            $results[0].PSObject.Properties.Name | Should -Contain 'SwitchName'
            $results[0].PSObject.Properties.Name | Should -Contain 'Status'
        }

        It 'each result Status is OK when creation succeeds' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT' }
            )
            $results = New-LabSwitch -Switches $switches
            $results | ForEach-Object { $_.Status | Should -Be 'OK' }
        }
    }

    Context '-All switch' {
        It 'reads switches from Get-LabNetworkConfig when -All is specified' {
            New-LabSwitch -All
            Should -Invoke Get-LabNetworkConfig -Times 1 -Exactly
        }

        It 'creates all switches from config when -All is used' {
            New-LabSwitch -All
            Should -Invoke New-VMSwitch -Times 2 -Exactly
        }

        It 'returns an array of results when -All is used' {
            $results = New-LabSwitch -All
            $results.Count | Should -Be 2
        }
    }

    Context 'single-switch backward compat' {
        It 'single-switch mode still works with just -SwitchName' {
            $result = New-LabSwitch -SwitchName 'MySingleSwitch'
            $result.SwitchName | Should -Be 'MySingleSwitch'
            $result.Status | Should -Be 'OK'
            Should -Invoke New-VMSwitch -Times 1 -Exactly
        }
    }
}

# --- New-LabNAT multi-switch support ------------------------------------------

Describe 'New-LabNAT - multi-switch' {

    BeforeEach {
        # Stub only what New-LabNAT actually calls (avoids Register-HyperVMocks
        # which requires Hyper-V cmdlets to exist before mocking)
        Mock Get-Module {
            [PSCustomObject]@{ Name = 'Hyper-V'; Version = '2.0.0.0' }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }

        Mock Get-LabConfig { $null }
        Mock Get-LabNetworkConfig {
            [PSCustomObject]@{
                Switches = @(
                    [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                    [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT' }
                )
                Subnet  = '10.0.10.0/24'
                Gateway = '10.0.10.1'
            }
        }
        Mock Get-VMSwitch { @() }
        Mock New-VMSwitch { [PSCustomObject]@{ Name = $Name; SwitchType = 'Internal' } }
        Mock Remove-VMSwitch { }
        Mock Get-NetIPAddress { @() }
        Mock New-NetIPAddress { }
        Mock Remove-NetIPAddress { }
        Mock Get-NetNat { @() }
        Mock New-NetNat { [PSCustomObject]@{ Name = $Name; InternalIPInterfaceAddressPrefix = $InternalIPInterfaceAddressPrefix } }
        Mock Remove-NetNat { }
        Mock Start-Sleep { }
        Mock Write-LabStatus { }
    }

    Context '-Switches parameter' {
        It 'configures NAT for each switch entry in -Switches array' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT' }
            )
            $results = New-LabNAT -Switches $switches
            Should -Invoke New-NetNat -Times 2 -Exactly
        }

        It 'returns an array of result objects when -Switches is used' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT' }
            )
            $results = New-LabNAT -Switches $switches
            $results.Count | Should -Be 2
        }

        It 'each result has OverallStatus OK when NAT creation succeeds' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
            )
            $results = New-LabNAT -Switches $switches
            $results[0].OverallStatus | Should -Be 'OK'
        }
    }

    Context '-All switch' {
        It 'reads switches from Get-LabNetworkConfig when -All is specified' {
            New-LabNAT -All
            Should -Invoke Get-LabNetworkConfig -Times 1 -Exactly
        }

        It 'configures NAT for all configured switches when -All is used' {
            New-LabNAT -All
            Should -Invoke New-NetNat -Times 2 -Exactly
        }

        It 'returns an array of results when -All is used' {
            $results = New-LabNAT -All
            $results.Count | Should -Be 2
        }
    }

    Context 'single-switch backward compat' {
        It 'single-switch mode still works with -SwitchName' {
            $result = New-LabNAT -SwitchName 'MySingleSwitch' -GatewayIP '10.99.0.1' -AddressSpace '10.99.0.0/24'
            $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
        }
    }
}

# --- Test-LabMultiSwitchSubnetOverlap -----------------------------------------

Describe 'Test-LabMultiSwitchSubnetOverlap' {

    Context 'non-overlapping subnets' {
        It 'returns HasOverlap = false for entirely distinct subnets' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '10.0.20.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.HasOverlap | Should -BeFalse
        }

        It 'returns an empty Overlaps array for non-overlapping subnets' {
            $switches = @(
                [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'LabDMZ'; AddressSpace = '192.168.1.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.Overlaps.Count | Should -Be 0
        }

        It 'handles a single switch with no conflicts (no pairs)' {
            $switches = @(
                [PSCustomObject]@{ Name = 'OnlySwitch'; AddressSpace = '10.0.10.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.HasOverlap | Should -BeFalse
        }
    }

    Context 'overlapping subnets' {
        It 'returns HasOverlap = true for identical subnets on different switches' {
            $switches = @(
                [PSCustomObject]@{ Name = 'Switch1'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'Switch2'; AddressSpace = '10.0.10.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.HasOverlap | Should -BeTrue
        }

        It 'returns the conflicting pair in Overlaps when subnets are identical' {
            $switches = @(
                [PSCustomObject]@{ Name = 'Switch1'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'Switch2'; AddressSpace = '10.0.10.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.Overlaps.Count | Should -Be 1
            $result.Overlaps[0].Switch1 | Should -Be 'Switch1'
            $result.Overlaps[0].Switch2 | Should -Be 'Switch2'
        }

        It 'detects partial overlap (supernet contains subnet)' {
            # 10.0.10.0/24 is wholly contained in 10.0.10.0/23
            $switches = @(
                [PSCustomObject]@{ Name = 'BigNet'; AddressSpace = '10.0.10.0/23' }
                [PSCustomObject]@{ Name = 'SmallNet'; AddressSpace = '10.0.10.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.HasOverlap | Should -BeTrue
        }

        It 'detects partial overlap when one subnet contains another' {
            # 10.0.10.0/25 is wholly contained within 10.0.10.0/24
            $switches = @(
                [PSCustomObject]@{ Name = 'WideNet'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'NarrowNet'; AddressSpace = '10.0.10.0/25' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.HasOverlap | Should -BeTrue
        }

        It 'detects multiple conflicts across three switches' {
            $switches = @(
                [PSCustomObject]@{ Name = 'S1'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'S2'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'S3'; AddressSpace = '10.0.10.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.HasOverlap | Should -BeTrue
            # 3 switches with identical subnets = 3 pairs: S1/S2, S1/S3, S2/S3
            $result.Overlaps.Count | Should -Be 3
        }
    }

    Context 'result structure' {
        It 'returns a result object with HasOverlap, Overlaps, and Message properties' {
            $switches = @(
                [PSCustomObject]@{ Name = 'NetA'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'NetB'; AddressSpace = '10.0.20.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.PSObject.Properties.Name | Should -Contain 'HasOverlap'
            $result.PSObject.Properties.Name | Should -Contain 'Overlaps'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Overlaps entries have Switch1, Switch2, Subnet1, Subnet2 properties' {
            $switches = @(
                [PSCustomObject]@{ Name = 'NetA'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'NetB'; AddressSpace = '10.0.10.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.Overlaps[0].PSObject.Properties.Name | Should -Contain 'Switch1'
            $result.Overlaps[0].PSObject.Properties.Name | Should -Contain 'Switch2'
            $result.Overlaps[0].PSObject.Properties.Name | Should -Contain 'Subnet1'
            $result.Overlaps[0].PSObject.Properties.Name | Should -Contain 'Subnet2'
        }

        It 'Message contains summary text' {
            $switches = @(
                [PSCustomObject]@{ Name = 'NetA'; AddressSpace = '10.0.10.0/24' }
                [PSCustomObject]@{ Name = 'NetB'; AddressSpace = '10.0.20.0/24' }
            )
            $result = Test-LabMultiSwitchSubnetOverlap -Switches $switches
            $result.Message | Should -Not -BeNullOrEmpty
        }
    }
}
