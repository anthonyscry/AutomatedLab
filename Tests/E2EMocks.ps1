# E2EMocks.ps1 -- Extended mock layer for E2E smoke tests
# Extends TestHelpers.ps1 with orchestrator-level mock infrastructure

$script:repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

# Call tracking for E2E assertions
$script:E2ECalls = @{
    Bootstrap = 0
    Deploy    = 0
    Teardown  = 0
    QuickDeploy = 0
    QuickTeardown = 0
    Setup     = 0
    HealthCheck = 0
}

# Test lab configuration matching $GlobalLabConfig structure
$script:TestLabConfig = @{
    Lab = @{
        Name = 'E2ETestLab'
        CoreVMNames = @('dc1', 'svr1', 'ws1')
        DomainName = 'e2etest.local'
        TimeZone = 'Pacific Standard Time'
    }
    Paths = @{
        LabRoot = 'C:\E2ELab'
        LabSourcesRoot = 'C:\E2ESources'
        UbuntuIso = 'C:\E2ESources\ubuntu.iso'
    }
    Network = @{
        SwitchName = 'E2ESwitch'
        NatName = 'E2ENat'
        AddressSpace = '172.16.0.0/24'
        SubnetPrefix = '172.16.0'
        PrefixLength = 24
    }
    VMSizing = @{
        Server = @{ Memory = 2GB; Processors = 2 }
        Client = @{ Memory = 2GB; Processors = 2 }
        Ubuntu = @{ Memory = 2GB; MinMemory = 1GB; MaxMemory = 4GB; Processors = 2 }
    }
    AutoHeal = @{
        Enabled = $true
        TimeoutSeconds = 5
        HealthCheckTimeoutSeconds = 2
    }
    Credentials = @{
        AdminPassword = 'E2ETestPass!'
        AdminUser = 'labadmin'
    }
}

function Register-E2EMocks {
    <#
    .SYNOPSIS
        Registers comprehensive mocks for E2E smoke testing.
    .DESCRIPTION
        Extends Register-HyperVMocks with orchestrator-level mocks needed
        to run OpenCodeLab-App.ps1 lifecycle actions without real infrastructure.
    #>

    # Reset call counters
    $script:E2ECalls = @{
        Bootstrap = 0
        Deploy    = 0
        Teardown  = 0
        QuickDeploy = 0
        QuickTeardown = 0
        Setup     = 0
        HealthCheck = 0
    }

    # Base Hyper-V mocks
    Register-HyperVMocks
}

function New-E2ERunLogDir {
    <#
    .SYNOPSIS
        Creates a temporary directory for run artifacts during E2E testing.
    .OUTPUTS
        [string] Path to the temporary run log directory.
    #>
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) 'E2ESmoke'
    $runDir = Join-Path $tempBase (Get-Date -Format 'yyyyMMdd-HHmmss')
    if (-not (Test-Path $runDir)) {
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    }
    return $runDir
}

function New-E2EStateProbe {
    <#
    .SYNOPSIS
        Creates a state probe object for E2E testing.
    .PARAMETER LabReady
        If true, simulates a lab with LabReady snapshots available (quick mode viable).
    .PARAMETER Clean
        If true, simulates a clean state (no VMs, no switch, no NAT).
    #>
    param(
        [switch]$LabReady,
        [switch]$Clean
    )

    if ($Clean) {
        return [pscustomobject]@{
            LabRegistered = $false
            MissingVMs = @('dc1', 'svr1', 'ws1')
            LabReadyAvailable = $false
            SwitchPresent = $false
            NatPresent = $false
        }
    }

    if ($LabReady) {
        return [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }
    }

    # Default: VMs exist but no snapshots
    return [pscustomobject]@{
        LabRegistered = $true
        MissingVMs = @()
        LabReadyAvailable = $false
        SwitchPresent = $true
        NatPresent = $true
    }
}
