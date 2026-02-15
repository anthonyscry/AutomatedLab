# Virtual switch subnet preflight conflict tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $helperPath = Join-Path $repoRoot 'Private/Test-LabVirtualSwitchSubnetConflict.ps1'
    if (Test-Path -Path $helperPath) {
        . $helperPath
    }
}

Describe 'Test-LabVirtualSwitchSubnetConflict' {
    AfterEach {
        foreach ($functionName in @('Get-NetIPAddress', 'Remove-NetIPAddress')) {
            if (Test-Path -Path ("Function:\$functionName")) {
                Remove-Item -Path ("Function:\$functionName") -Force
            }
        }
    }

    It 'detects conflicting vEthernet adapters on the same subnet' {
        function Get-NetIPAddress {
            @(
                [pscustomobject]@{ InterfaceAlias = 'vEthernet (AutomatedLab)'; IPAddress = '10.0.10.1'; PrefixLength = 24 },
                [pscustomobject]@{ InterfaceAlias = 'vEthernet (OtherLab)'; IPAddress = '10.0.10.2'; PrefixLength = 24 },
                [pscustomobject]@{ InterfaceAlias = 'Ethernet'; IPAddress = '192.168.1.25'; PrefixLength = 24 }
            )
        }

        $result = Test-LabVirtualSwitchSubnetConflict -SwitchName 'AutomatedLab' -AddressSpace '10.0.10.0/24'

        $result.HasConflict | Should -BeTrue
        $result.ConflictingAdapters.Count | Should -Be 1
        $result.ConflictingAdapters[0].InterfaceAlias | Should -Be 'vEthernet (OtherLab)'
        $result.ConflictingAdapters[0].SwitchName | Should -Be 'OtherLab'
        $result.AutoFixApplied | Should -BeFalse
    }

    It 'auto-fixes removable subnet conflicts when requested' {
        $script:ipRows = @(
            [pscustomobject]@{ InterfaceAlias = 'vEthernet (AutomatedLab)'; IPAddress = '10.0.10.1'; PrefixLength = 24 },
            [pscustomobject]@{ InterfaceAlias = 'vEthernet (OtherLab)'; IPAddress = '10.0.10.2'; PrefixLength = 24 }
        )

        function Get-NetIPAddress {
            @($script:ipRows)
        }

        function Remove-NetIPAddress {
            param(
                [string]$InterfaceAlias,
                [string]$IPAddress,
                [switch]$Confirm,
                [string]$ErrorAction
            )

            $script:ipRows = @(
                $script:ipRows | Where-Object {
                    -not ($_.InterfaceAlias -eq $InterfaceAlias -and $_.IPAddress -eq $IPAddress)
                }
            )
        }

        $result = Test-LabVirtualSwitchSubnetConflict -SwitchName 'AutomatedLab' -AddressSpace '10.0.10.0/24' -AutoFix

        $result.HasConflict | Should -BeFalse
        $result.AutoFixApplied | Should -BeTrue
        $result.ConflictingAdapters.Count | Should -Be 1
        $result.FixedAdapters.Count | Should -Be 1
        $result.UnresolvedAdapters.Count | Should -Be 0
        $script:ipRows.Count | Should -Be 1
        $script:ipRows[0].InterfaceAlias | Should -Be 'vEthernet (AutomatedLab)'
    }

    It 'keeps conflicts unresolved when auto-fix removal fails' {
        function Get-NetIPAddress {
            @(
                [pscustomobject]@{ InterfaceAlias = 'vEthernet (AutomatedLab)'; IPAddress = '10.0.10.1'; PrefixLength = 24 },
                [pscustomobject]@{ InterfaceAlias = 'vEthernet (OtherLab)'; IPAddress = '10.0.10.2'; PrefixLength = 24 }
            )
        }

        function Remove-NetIPAddress {
            param(
                [string]$InterfaceAlias,
                [string]$IPAddress,
                [switch]$Confirm,
                [string]$ErrorAction
            )

            throw 'Simulated remove failure'
        }

        $result = Test-LabVirtualSwitchSubnetConflict -SwitchName 'AutomatedLab' -AddressSpace '10.0.10.0/24' -AutoFix

        $result.HasConflict | Should -BeTrue
        $result.AutoFixApplied | Should -BeFalse
        $result.UnresolvedAdapters.Count | Should -Be 1
        $result.UnresolvedAdapters[0].Error | Should -Match 'Simulated remove failure'
    }
}
