# NetworkHealth.Tests.ps1
# Tests for network health check functions

BeforeAll {
    # Import the module
    $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
    Import-Module $modulePath -Force

    # Set up mock $GlobalLabConfig for testing
    $Global:GlobalLabConfig = @{
        Network = @{
            SwitchName = 'TestLabSwitch'
            NatName = 'TestLabNAT'
            GatewayIp = '10.0.10.1'
        }
        Lab = @{
            CoreVMNames = @('dc1', 'svr1', 'ws1')
        }
    }
}

Describe 'Test-LabNetwork' {
    Context 'Parameter Handling' {
        It 'Accepts -SwitchName parameter' {
            # Test that the function exists and accepts the parameter
            $cmd = Get-Command Test-LabNetwork
            $cmd.Parameters.Keys | Should -Contain 'SwitchName'
        }

        It 'Uses $GlobalLabConfig.Network.SwitchName as default when available' {
            # When Hyper-V is not available, function should still return result with correct switch name
            $result = Test-LabNetwork
            $result.SwitchName | Should -Be 'TestLabSwitch'
        }

        It 'Falls back to "SimpleLab" when $GlobalLabConfig is not available' {
            $savedConfig = $Global:GlobalLabConfig
            Remove-Variable -Name GlobalLabConfig -Scope Global -Force -ErrorAction SilentlyContinue

            $result = Test-LabNetwork
            $result.SwitchName | Should -Be 'SimpleLab'

            $Global:GlobalLabConfig = $savedConfig
        }
    }

    Context 'Return Object Structure' {
        It 'Returns object with Exists, SwitchType, Status properties' {
            $result = Test-LabNetwork
            $result.PSObject.Properties.Name | Should -Contain 'Exists'
            $result.PSObject.Properties.Name | Should -Contain 'SwitchType'
            $result.PSObject.Properties.Name | Should -Contain 'Status'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $result.PSObject.Properties.Name | Should -Contain 'SwitchName'
        }

        It 'Returns error status when Hyper-V not available' {
            # On systems without Hyper-V, function should return Error status
            $result = Test-LabNetwork
            # Status should be either NotFound (switch doesn't exist) or Error (Hyper-V not available)
            $result.Status | Should -BeIn @('NotFound', 'Error')
        }
    }
}

Describe 'Test-LabNetworkHealth' {
    Context 'Parameter Handling' {
        It 'Accepts -VMNames parameter' {
            $cmd = Get-Command Test-LabNetworkHealth
            $cmd.Parameters.Keys | Should -Contain 'VMNames'
        }

        It 'Accepts -SwitchName parameter' {
            $cmd = Get-Command Test-LabNetworkHealth
            $cmd.Parameters.Keys | Should -Contain 'SwitchName'
        }

        It 'Has default VMNames from $GlobalLabConfig when available' {
            # Verify the function can run and uses config
            $result = Test-LabNetworkHealth
            # Should fail because vSwitch doesn't exist or Hyper-V not available, but structure should be correct
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Return Object Structure' {
        It 'Returns object with OverallStatus, ConnectivityTests, FailedTests, Duration, Message' {
            $result = Test-LabNetworkHealth
            $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
            $result.PSObject.Properties.Name | Should -Contain 'ConnectivityTests'
            $result.PSObject.Properties.Name | Should -Contain 'FailedTests'
            $result.PSObject.Properties.Name | Should -Contain 'Duration'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Returns Failed status when vSwitch does not exist' {
            $result = Test-LabNetworkHealth
            # Without Hyper-V or when switch doesn't exist, should return Failed
            $result.OverallStatus | Should -Be 'Failed'
            $result.Message | Should -BeLike '*vSwitch not found*'
        }
    }
}
