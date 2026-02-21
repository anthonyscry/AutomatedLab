# ComplexNetworking-VMAssignment.Tests.ps1
# Tests for VM-to-switch assignment, VLAN tagging, and inter-subnet routing.
# Phase 23, Plan 02 -- Complex Networking

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    . (Join-Path $script:repoRoot 'Private' 'Get-LabNetworkConfig.ps1')
    . (Join-Path $script:repoRoot 'Private' 'New-LabVMNetworkAdapter.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Initialize-LabNetwork.ps1')

    # Stub dependencies not under test (loaded on demand to avoid module conflicts)
    if (-not (Get-Command Get-LabConfig -ErrorAction SilentlyContinue)) {
        function Get-LabConfig { $null }
    }
    if (-not (Get-Command Write-LabStatus -ErrorAction SilentlyContinue)) {
        function Write-LabStatus { param($Status, $Message, $Indent) }
    }
    if (-not (Get-Command Set-VMStaticIP -ErrorAction SilentlyContinue)) {
        function Set-VMStaticIP {
            param($VMName, $IPAddress, $PrefixLength)
            [PSCustomObject]@{ VMName = $VMName; IPAddress = $IPAddress; Configured = $true; Status = 'OK'; Message = "OK" }
        }
    }

    # Stub Hyper-V cmdlets that don't exist in non-Hyper-V environments (WSL/CI).
    # Pester requires a command to exist before it can be mocked.
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        function Get-VM { param($Name) @() }
    }
    if (-not (Get-Command Get-VMNetworkAdapter -ErrorAction SilentlyContinue)) {
        function Get-VMNetworkAdapter { param($VMName) @() }
    }
    if (-not (Get-Command Connect-VMNetworkAdapter -ErrorAction SilentlyContinue)) {
        function Connect-VMNetworkAdapter { param($VMName, $SwitchName, $VMNetworkAdapter) }
    }
    if (-not (Get-Command Set-VMNetworkAdapterVlan -ErrorAction SilentlyContinue)) {
        function Set-VMNetworkAdapterVlan { param($VMName, [switch]$Access, $VlanId) }
    }
    if (-not (Get-Command Get-VMNetworkAdapterVlan -ErrorAction SilentlyContinue)) {
        function Get-VMNetworkAdapterVlan { param($VMName) [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 } }
    }
    if (-not (Get-Command New-NetRoute -ErrorAction SilentlyContinue)) {
        function New-NetRoute { param($DestinationPrefix, $InterfaceAlias, $NextHop, $RouteMetric) }
    }
    if (-not (Get-Command Get-NetRoute -ErrorAction SilentlyContinue)) {
        function Get-NetRoute { param($DestinationPrefix, $ErrorAction) @() }
    }
    if (-not (Get-Command Get-Module -ErrorAction SilentlyContinue)) {
        # Get-Module always exists in PS but may not return Hyper-V in CI
    }
    # Invoke-LabGatewayForwarding is a lab-private wrapper around Invoke-Command -VMName
    # (avoids Pester/Invoke-Command parameter-set binding issues in non-Hyper-V environments)
    if (-not (Get-Command Invoke-LabGatewayForwarding -ErrorAction SilentlyContinue)) {
        function Invoke-LabGatewayForwarding { param($VMName) }
    }
}

Describe 'Get-LabNetworkConfig - VMAssignments from IPPlan' {

    Context 'when IPPlan has hashtable entries with Switch and VlanId' {
        BeforeEach {
            $script:savedGlobalLabConfig = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'LabCorpNet'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'LabCorpNetNAT'
                    Switches = @(
                        @{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                        @{ Name = 'LabDMZ';     AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT'     }
                    )
                    Routing = @{
                        Mode = 'host'; GatewayVM = ''; EnableForwarding = $true
                    }
                }
                IPPlan = @{
                    DC1  = @{ IP = '10.0.10.10'; Switch = 'LabCorpNet' }
                    SVR1 = @{ IP = '10.0.10.20'; Switch = 'LabCorpNet'; VlanId = 100 }
                    WS1  = @{ IP = '10.0.20.30'; Switch = 'LabDMZ';     VlanId = 200 }
                    DSC1 = '10.0.10.40'
                    LIN1 = @{ IP = '10.0.10.110'; Switch = 'LabCorpNet' }
                }
            }
            Mock Get-LabConfig { $null }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfig) {
                $GlobalLabConfig = $script:savedGlobalLabConfig
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'returns VMAssignments property' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments | Should -Not -BeNullOrEmpty
        }

        It 'VMAssignments contains correct Switch for DC1' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['DC1'].Switch | Should -Be 'LabCorpNet'
        }

        It 'VMAssignments contains correct IP for DC1' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['DC1'].IP | Should -Be '10.0.10.10'
        }

        It 'VMAssignments contains null VlanId for DC1 (no VLAN specified)' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['DC1'].VlanId | Should -BeNullOrEmpty
        }

        It 'VMAssignments contains correct Switch for SVR1' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['SVR1'].Switch | Should -Be 'LabCorpNet'
        }

        It 'VMAssignments contains correct VlanId for SVR1' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['SVR1'].VlanId | Should -Be 100
        }

        It 'VMAssignments contains correct Switch for WS1' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['WS1'].Switch | Should -Be 'LabDMZ'
        }

        It 'VMAssignments contains correct VlanId for WS1' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['WS1'].VlanId | Should -Be 200
        }

        It 'VMAssignments contains correct IP for WS1 on DMZ switch' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['WS1'].IP | Should -Be '10.0.20.30'
        }
    }

    Context 'when IPPlan has a plain string entry (backward compat)' {
        BeforeEach {
            $script:savedGlobalLabConfig2 = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'LabCorpNet'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'LabCorpNetNAT'
                    Switches = @(
                        @{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                    )
                }
                IPPlan = @{
                    DSC1 = '10.0.10.40'
                }
            }
            Mock Get-LabConfig { $null }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfig2) {
                $GlobalLabConfig = $script:savedGlobalLabConfig2
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'backward compat: plain string IPPlan entry is in VMAssignments' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments.ContainsKey('DSC1') | Should -BeTrue
        }

        It 'backward compat: plain string IP resolves correctly' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['DSC1'].IP | Should -Be '10.0.10.40'
        }

        It 'backward compat: plain string entry maps to the first/default switch' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['DSC1'].Switch | Should -Be 'LabCorpNet'
        }

        It 'backward compat: plain string entry has null VlanId' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMAssignments['DSC1'].VlanId | Should -BeNullOrEmpty
        }

        It 'backward compat: VMIPs property still works (flat name-to-IP)' {
            $cfg = Get-LabNetworkConfig
            $cfg.VMIPs['DSC1'] | Should -Be '10.0.10.40'
        }
    }

    Context 'when Routing config is specified' {
        BeforeEach {
            $script:savedGlobalLabConfig3 = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'LabCorpNet'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'LabCorpNetNAT'
                    Switches = @(
                        @{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                    )
                    Routing = @{
                        Mode             = 'gateway'
                        GatewayVM        = 'GW1'
                        EnableForwarding = $true
                    }
                }
                IPPlan = @{ DC1 = '10.0.10.10' }
            }
            Mock Get-LabConfig { $null }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfig3) {
                $GlobalLabConfig = $script:savedGlobalLabConfig3
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'returns Routing property' {
            $cfg = Get-LabNetworkConfig
            $cfg.Routing | Should -Not -BeNullOrEmpty
        }

        It 'Routing.Mode is gateway' {
            $cfg = Get-LabNetworkConfig
            $cfg.Routing.Mode | Should -Be 'gateway'
        }

        It 'Routing.GatewayVM is GW1' {
            $cfg = Get-LabNetworkConfig
            $cfg.Routing.GatewayVM | Should -Be 'GW1'
        }

        It 'Routing.EnableForwarding is true' {
            $cfg = Get-LabNetworkConfig
            $cfg.Routing.EnableForwarding | Should -BeTrue
        }
    }

    Context 'when Routing config is absent (returns defaults)' {
        BeforeEach {
            $script:savedGlobalLabConfig4 = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'SimpleLab'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'SimpleLabNAT'
                }
                IPPlan = @{ DC1 = '10.0.10.10' }
            }
            Mock Get-LabConfig { $null }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfig4) {
                $GlobalLabConfig = $script:savedGlobalLabConfig4
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Routing.Mode defaults to host when not specified' {
            $cfg = Get-LabNetworkConfig
            $cfg.Routing.Mode | Should -Be 'host'
        }

        It 'Routing.GatewayVM defaults to empty string when not specified' {
            $cfg = Get-LabNetworkConfig
            $cfg.Routing.GatewayVM | Should -Be ''
        }
    }
}

# --- New-LabVMNetworkAdapter tests -------------------------------------------

Describe 'New-LabVMNetworkAdapter' {

    Context 'when connecting VM to named switch (no VLAN)' {
        BeforeEach {
            Mock Get-VM {
                [PSCustomObject]@{ Name = 'DC1'; State = 'Running' }
            }
            Mock Get-VMNetworkAdapter {
                [PSCustomObject]@{ VMName = 'DC1'; SwitchName = '' }
            }
            Mock Connect-VMNetworkAdapter { }
            Mock Set-VMNetworkAdapterVlan { }
            Mock Get-VMNetworkAdapterVlan {
                [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
            }
        }

        It 'returns a result object' {
            $result = New-LabVMNetworkAdapter -VMName 'DC1' -SwitchName 'LabCorpNet'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'result has VMName property' {
            $result = New-LabVMNetworkAdapter -VMName 'DC1' -SwitchName 'LabCorpNet'
            $result.VMName | Should -Be 'DC1'
        }

        It 'result has SwitchName property' {
            $result = New-LabVMNetworkAdapter -VMName 'DC1' -SwitchName 'LabCorpNet'
            $result.SwitchName | Should -Be 'LabCorpNet'
        }

        It 'result Status is OK' {
            $result = New-LabVMNetworkAdapter -VMName 'DC1' -SwitchName 'LabCorpNet'
            $result.Status | Should -Be 'OK'
        }

        It 'calls Connect-VMNetworkAdapter' {
            New-LabVMNetworkAdapter -VMName 'DC1' -SwitchName 'LabCorpNet' | Out-Null
            Should -Invoke Connect-VMNetworkAdapter -Times 1
        }

        It 'does not call Set-VMNetworkAdapterVlan when no VlanId specified' {
            New-LabVMNetworkAdapter -VMName 'DC1' -SwitchName 'LabCorpNet' | Out-Null
            Should -Invoke Set-VMNetworkAdapterVlan -Times 0
        }
    }

    Context 'when VlanId > 0 is specified' {
        BeforeEach {
            Mock Get-VM {
                [PSCustomObject]@{ Name = 'SVR1'; State = 'Running' }
            }
            Mock Get-VMNetworkAdapter {
                [PSCustomObject]@{ VMName = 'SVR1'; SwitchName = '' }
            }
            Mock Connect-VMNetworkAdapter { }
            Mock Set-VMNetworkAdapterVlan { }
            Mock Get-VMNetworkAdapterVlan {
                [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
            }
        }

        It 'calls Set-VMNetworkAdapterVlan when VlanId is 100' {
            New-LabVMNetworkAdapter -VMName 'SVR1' -SwitchName 'LabCorpNet' -VlanId 100 | Out-Null
            Should -Invoke Set-VMNetworkAdapterVlan -Times 1
        }

        It 'result VlanId is 100' {
            $result = New-LabVMNetworkAdapter -VMName 'SVR1' -SwitchName 'LabCorpNet' -VlanId 100
            $result.VlanId | Should -Be 100
        }
    }

    Context 'idempotent: adapter already on correct switch and correct VLAN' {
        BeforeEach {
            Mock Get-VM {
                [PSCustomObject]@{ Name = 'DC1'; State = 'Running' }
            }
            Mock Get-VMNetworkAdapter {
                [PSCustomObject]@{ VMName = 'DC1'; SwitchName = 'LabCorpNet' }
            }
            Mock Get-VMNetworkAdapterVlan {
                [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
            }
            Mock Connect-VMNetworkAdapter { }
            Mock Set-VMNetworkAdapterVlan { }
        }

        It 'returns OK without calling Connect-VMNetworkAdapter again' {
            $result = New-LabVMNetworkAdapter -VMName 'DC1' -SwitchName 'LabCorpNet'
            $result.Status | Should -Be 'OK'
            Should -Invoke Connect-VMNetworkAdapter -Times 0
        }
    }

    Context 'when VM does not exist' {
        BeforeEach {
            Mock Get-VM { $null }
        }

        It 'returns Failed status' {
            $result = New-LabVMNetworkAdapter -VMName 'NOSUCHVM' -SwitchName 'LabCorpNet'
            $result.Status | Should -Be 'Failed'
        }
    }
}

# --- Initialize-LabNetwork multi-subnet tests ---------------------------------

Describe 'Initialize-LabNetwork - multi-subnet' {

    Context 'multi-subnet: each VM gets correct switch and IP' {
        BeforeEach {
            $script:savedGlobalLabConfigInit = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'LabCorpNet'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'LabCorpNetNAT'
                    Switches = @(
                        @{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                        @{ Name = 'LabDMZ';     AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT'     }
                    )
                    Routing = @{ Mode = 'host'; GatewayVM = ''; EnableForwarding = $true }
                }
                IPPlan = @{
                    DC1  = @{ IP = '10.0.10.10'; Switch = 'LabCorpNet' }
                    WS1  = @{ IP = '10.0.20.30'; Switch = 'LabDMZ'; VlanId = 200 }
                }
            }
            Mock Get-LabConfig { $null }
            Mock Set-VMStaticIP {
                param($VMName, $IPAddress, $PrefixLength)
                [PSCustomObject]@{ VMName = $VMName; IPAddress = $IPAddress; Configured = $true; Status = 'OK'; Message = 'OK' }
            }
            Mock Get-VM { [PSCustomObject]@{ Name = $Name; State = 'Running' } }
            Mock Get-VMNetworkAdapter {
                [PSCustomObject]@{ VMName = $VMName; SwitchName = '' }
            }
            Mock Connect-VMNetworkAdapter { }
            Mock Set-VMNetworkAdapterVlan { }
            Mock Get-VMNetworkAdapterVlan {
                [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
            }
            Mock New-NetRoute { }
            Mock Get-NetRoute { @() }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfigInit) {
                $GlobalLabConfig = $script:savedGlobalLabConfigInit
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'configures DC1 on LabCorpNet with correct IP' {
            $result = Initialize-LabNetwork -VMNames @('DC1', 'WS1')
            $result.VMConfigured['DC1'].IPAddress | Should -Be '10.0.10.10'
        }

        It 'configures WS1 on LabDMZ with correct IP' {
            $result = Initialize-LabNetwork -VMNames @('DC1', 'WS1')
            $result.VMConfigured['WS1'].IPAddress | Should -Be '10.0.20.30'
        }

        It 'returns OK overall status when all VMs succeed' {
            $result = Initialize-LabNetwork -VMNames @('DC1', 'WS1')
            $result.OverallStatus | Should -Be 'OK'
        }

        It 'calls New-LabVMNetworkAdapter for each VM (via Connect-VMNetworkAdapter)' {
            Initialize-LabNetwork -VMNames @('DC1', 'WS1') | Out-Null
            Should -Invoke Connect-VMNetworkAdapter -Times 2
        }
    }

    Context 'host routing mode: New-NetRoute called for cross-subnet routes' {
        BeforeEach {
            $script:savedGlobalLabConfigRoute = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'LabCorpNet'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'LabCorpNetNAT'
                    Switches = @(
                        @{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                        @{ Name = 'LabDMZ';     AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT'     }
                    )
                    Routing = @{ Mode = 'host'; GatewayVM = ''; EnableForwarding = $true }
                }
                IPPlan = @{
                    DC1 = @{ IP = '10.0.10.10'; Switch = 'LabCorpNet' }
                    WS1 = @{ IP = '10.0.20.30'; Switch = 'LabDMZ' }
                }
            }
            Mock Get-LabConfig { $null }
            Mock Set-VMStaticIP {
                param($VMName, $IPAddress, $PrefixLength)
                [PSCustomObject]@{ VMName = $VMName; IPAddress = $IPAddress; Configured = $true; Status = 'OK'; Message = 'OK' }
            }
            Mock Get-VM { [PSCustomObject]@{ Name = $Name; State = 'Running' } }
            Mock Get-VMNetworkAdapter {
                [PSCustomObject]@{ VMName = $VMName; SwitchName = '' }
            }
            Mock Connect-VMNetworkAdapter { }
            Mock Set-VMNetworkAdapterVlan { }
            Mock Get-VMNetworkAdapterVlan {
                [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
            }
            Mock New-NetRoute { }
            Mock Get-NetRoute { @() }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfigRoute) {
                $GlobalLabConfig = $script:savedGlobalLabConfigRoute
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'calls New-NetRoute at least once when host routing mode is active with 2 switches' {
            Initialize-LabNetwork -VMNames @('DC1', 'WS1') | Out-Null
            Should -Invoke New-NetRoute -Times 1 -Exactly:$false
        }
    }

    Context 'gateway routing mode: IP forwarding enabled on gateway VM' {
        BeforeEach {
            $script:savedGlobalLabConfigGW = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'LabCorpNet'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'LabCorpNetNAT'
                    Switches = @(
                        @{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24'; GatewayIp = '10.0.10.1'; NatName = 'LabCorpNetNAT' }
                        @{ Name = 'LabDMZ';     AddressSpace = '10.0.20.0/24'; GatewayIp = '10.0.20.1'; NatName = 'LabDMZNAT'     }
                    )
                    Routing = @{ Mode = 'gateway'; GatewayVM = 'GW1'; EnableForwarding = $true }
                }
                IPPlan = @{
                    DC1 = @{ IP = '10.0.10.10'; Switch = 'LabCorpNet' }
                }
            }
            Mock Get-LabConfig { $null }
            Mock Set-VMStaticIP {
                param($VMName, $IPAddress, $PrefixLength)
                [PSCustomObject]@{ VMName = $VMName; IPAddress = $IPAddress; Configured = $true; Status = 'OK'; Message = 'OK' }
            }
            Mock Get-VM { [PSCustomObject]@{ Name = $Name; State = 'Running' } }
            Mock Get-VMNetworkAdapter {
                [PSCustomObject]@{ VMName = $VMName; SwitchName = '' }
            }
            Mock Connect-VMNetworkAdapter { }
            Mock Set-VMNetworkAdapterVlan { }
            Mock Get-VMNetworkAdapterVlan {
                [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
            }
            Mock New-NetRoute { }
            Mock Get-NetRoute { @() }
            Mock Invoke-LabGatewayForwarding { }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfigGW) {
                $GlobalLabConfig = $script:savedGlobalLabConfigGW
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'calls Invoke-LabGatewayForwarding on the gateway VM when gateway routing mode is active' {
            Initialize-LabNetwork -VMNames @('DC1') | Out-Null
            Should -Invoke Invoke-LabGatewayForwarding -Times 1
        }
    }

    Context 'backward compat: single-subnet config uses existing flow' {
        BeforeEach {
            $script:savedGlobalLabConfigBC = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig } else { $null }
            $GlobalLabConfig = @{
                Network = @{
                    SwitchName   = 'SimpleLab'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'SimpleLabNAT'
                }
                IPPlan = @{
                    DC1  = '10.0.10.10'
                    SVR1 = '10.0.10.20'
                }
            }
            Mock Get-LabConfig { $null }
            Mock Set-VMStaticIP {
                param($VMName, $IPAddress, $PrefixLength)
                [PSCustomObject]@{ VMName = $VMName; IPAddress = $IPAddress; Configured = $true; Status = 'OK'; Message = 'OK' }
            }
            Mock Get-VM { [PSCustomObject]@{ Name = $Name; State = 'Running' } }
            Mock Get-VMNetworkAdapter {
                [PSCustomObject]@{ VMName = $VMName; SwitchName = 'SimpleLab' }
            }
            Mock Get-VMNetworkAdapterVlan {
                [PSCustomObject]@{ OperationMode = 'Untagged'; AccessVlanId = 0 }
            }
            Mock Connect-VMNetworkAdapter { }
            Mock Set-VMNetworkAdapterVlan { }
            Mock New-NetRoute { }
            Mock Get-NetRoute { @() }
        }
        AfterEach {
            if ($null -ne $script:savedGlobalLabConfigBC) {
                $GlobalLabConfig = $script:savedGlobalLabConfigBC
            }
            else {
                Remove-Variable -Name GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'backward compat: DC1 resolves to 10.0.10.10' {
            $result = Initialize-LabNetwork -VMNames @('DC1')
            $result.VMConfigured['DC1'].IPAddress | Should -Be '10.0.10.10'
        }

        It 'backward compat: returns OK overall status' {
            $result = Initialize-LabNetwork -VMNames @('DC1', 'SVR1')
            $result.OverallStatus | Should -Be 'OK'
        }

        It 'backward compat: does not call New-NetRoute for single-subnet config' {
            Initialize-LabNetwork -VMNames @('DC1', 'SVR1') | Out-Null
            Should -Invoke New-NetRoute -Times 0
        }
    }
}
