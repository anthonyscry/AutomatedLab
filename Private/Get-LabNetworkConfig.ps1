function Get-LabNetworkConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Get lab configuration
        $labConfig = Get-LabConfig

        # Initialize default network configuration
        $defaultConfig = [PSCustomObject]@{
            Subnet = "10.0.10.0/24"
            PrefixLength = 24
            Gateway = "10.0.10.1"
            DNSServers = @("10.0.10.10")
            VMIPs = @{
                "dc1"  = "10.0.10.10"
                "svr1" = "10.0.10.20"
                "ws1"  = "10.0.10.30"
                "dsc"  = "10.0.10.40"
            }
            Switches = @(
                [PSCustomObject]@{
                    Name         = 'SimpleLab'
                    AddressSpace = '10.0.10.0/24'
                    GatewayIp    = '10.0.10.1'
                    NatName      = 'SimpleLabNAT'
                }
            )
        }

        # Helper: normalize a switch entry (hashtable or PSCustomObject) to PSCustomObject
        function ConvertTo-SwitchEntry {
            param([object]$Entry)
            $name      = if ($Entry -is [hashtable]) { $Entry['Name'] }      else { $Entry.Name }
            $addrSpace = if ($Entry -is [hashtable]) { $Entry['AddressSpace'] } else { $Entry.AddressSpace }
            $gatewayIp = if ($Entry -is [hashtable]) { $Entry['GatewayIp'] }  else { $Entry.GatewayIp }
            $natName   = if ($Entry -is [hashtable]) { $Entry['NatName'] }    else { $Entry.NatName }
            if ([string]::IsNullOrWhiteSpace($natName)) {
                $natName = "${name}NAT"
            }
            [PSCustomObject]@{
                Name         = $name
                AddressSpace = $addrSpace
                GatewayIp    = $gatewayIp
                NatName      = $natName
            }
        }

        # Determine the switches array to use (priority order):
        # 1. Get-LabConfig returns NetworkConfiguration.Switches
        # 2. $GlobalLabConfig.Network.Switches (set by Lab-Config.ps1)
        # 3. Fallback: build a single-switch entry from flat Network keys

        $switchesArray = $null

        if ($null -ne $labConfig -and
            ($labConfig.PSObject.Properties.Name -contains 'NetworkConfiguration') -and
            ($null -ne $labConfig.NetworkConfiguration) -and
            ($labConfig.NetworkConfiguration.PSObject.Properties.Name -contains 'Switches') -and
            ($null -ne $labConfig.NetworkConfiguration.Switches) -and
            ($labConfig.NetworkConfiguration.Switches.Count -gt 0)) {

            $switchesArray = @($labConfig.NetworkConfiguration.Switches | ForEach-Object {
                ConvertTo-SwitchEntry -Entry $_
            })
        }
        elseif ((Test-Path variable:GlobalLabConfig) -and
                $null -ne $GlobalLabConfig -and
                $GlobalLabConfig -is [hashtable] -and
                $GlobalLabConfig.ContainsKey('Network') -and
                $GlobalLabConfig.Network.ContainsKey('Switches') -and
                $null -ne $GlobalLabConfig.Network.Switches -and
                $GlobalLabConfig.Network.Switches.Count -gt 0) {

            $switchesArray = @($GlobalLabConfig.Network.Switches | ForEach-Object {
                ConvertTo-SwitchEntry -Entry $_
            })
        }
        else {
            # Backward compat: build single-switch entry from flat Network keys
            $flatSwitchName   = 'SimpleLab'
            $flatAddressSpace = '10.0.10.0/24'
            $flatGatewayIp    = '10.0.10.1'
            $flatNatName      = 'SimpleLabNAT'

            if ((Test-Path variable:GlobalLabConfig) -and
                $null -ne $GlobalLabConfig -and
                $GlobalLabConfig -is [hashtable] -and
                $GlobalLabConfig.ContainsKey('Network')) {

                $net = $GlobalLabConfig.Network
                if ($net.ContainsKey('SwitchName')   -and -not [string]::IsNullOrWhiteSpace($net['SwitchName']))   { $flatSwitchName   = $net['SwitchName']   }
                if ($net.ContainsKey('AddressSpace')  -and -not [string]::IsNullOrWhiteSpace($net['AddressSpace'])) { $flatAddressSpace  = $net['AddressSpace']  }
                if ($net.ContainsKey('GatewayIp')     -and -not [string]::IsNullOrWhiteSpace($net['GatewayIp']))    { $flatGatewayIp    = $net['GatewayIp']     }
                if ($net.ContainsKey('NatName')       -and -not [string]::IsNullOrWhiteSpace($net['NatName']))      { $flatNatName      = $net['NatName']       }
            }

            $switchesArray = @(
                [PSCustomObject]@{
                    Name         = $flatSwitchName
                    AddressSpace = $flatAddressSpace
                    GatewayIp    = $flatGatewayIp
                    NatName      = $flatNatName
                }
            )
        }

        # If no config exists, return defaults with Switches
        if ($null -eq $labConfig) {
            # Still attempt to build from GlobalLabConfig if present
            $result = [PSCustomObject]@{
                Subnet       = $defaultConfig.Subnet
                PrefixLength = $defaultConfig.PrefixLength
                Gateway      = $defaultConfig.Gateway
                DNSServers   = $defaultConfig.DNSServers
                VMIPs        = $defaultConfig.VMIPs
                Switches     = $switchesArray
            }
            return $result
        }

        # Check if NetworkConfiguration section exists
        if ($labConfig.PSObject.Properties.Name -contains 'NetworkConfiguration') {
            $networkConfig = $labConfig.NetworkConfiguration

            # Build result object from config, using defaults for missing properties
            $result = [PSCustomObject]@{
                Subnet       = if ($networkConfig.PSObject.Properties.Name -contains 'Subnet')       { $networkConfig.Subnet }       else { $defaultConfig.Subnet }
                PrefixLength = if ($networkConfig.PSObject.Properties.Name -contains 'PrefixLength') { $networkConfig.PrefixLength } else { $defaultConfig.PrefixLength }
                Gateway      = if ($networkConfig.PSObject.Properties.Name -contains 'Gateway')      { $networkConfig.Gateway }      else { $defaultConfig.Gateway }
                DNSServers   = if ($networkConfig.PSObject.Properties.Name -contains 'DNSServers')   { $networkConfig.DNSServers }   else { $defaultConfig.DNSServers }
                VMIPs        = if ($networkConfig.PSObject.Properties.Name -contains 'VMIPs')        { $networkConfig.VMIPs }        else { $defaultConfig.VMIPs }
                Switches     = $switchesArray
            }

            return $result
        }

        # Return defaults if NetworkConfiguration section doesn't exist
        $result = [PSCustomObject]@{
            Subnet       = $defaultConfig.Subnet
            PrefixLength = $defaultConfig.PrefixLength
            Gateway      = $defaultConfig.Gateway
            DNSServers   = $defaultConfig.DNSServers
            VMIPs        = $defaultConfig.VMIPs
            Switches     = $switchesArray
        }
        return $result
    }
    catch {
        throw "Get-LabNetworkConfig: failed to build network configuration - $_"
    }
}
