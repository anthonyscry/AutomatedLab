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
        }

        # If no config exists, return defaults
        if ($null -eq $labConfig) {
            return $defaultConfig
        }

        # Check if NetworkConfiguration section exists
        if ($labConfig.PSObject.Properties.Name -contains 'NetworkConfiguration') {
            $networkConfig = $labConfig.NetworkConfiguration

            # Build result object from config, using defaults for missing properties
            $result = [PSCustomObject]@{
                Subnet = if ($networkConfig.PSObject.Properties.Name -contains 'Subnet') { $networkConfig.Subnet } else { $defaultConfig.Subnet }
                PrefixLength = if ($networkConfig.PSObject.Properties.Name -contains 'PrefixLength') { $networkConfig.PrefixLength } else { $defaultConfig.PrefixLength }
                Gateway = if ($networkConfig.PSObject.Properties.Name -contains 'Gateway') { $networkConfig.Gateway } else { $defaultConfig.Gateway }
                DNSServers = if ($networkConfig.PSObject.Properties.Name -contains 'DNSServers') { $networkConfig.DNSServers } else { $defaultConfig.DNSServers }
                VMIPs = if ($networkConfig.PSObject.Properties.Name -contains 'VMIPs') { $networkConfig.VMIPs } else { $defaultConfig.VMIPs }
            }

            return $result
        }

        # Return defaults if NetworkConfiguration section doesn't exist
        return $defaultConfig
    }
    catch {
        throw "Get-LabNetworkConfig: failed to build network configuration - $_"
    }
}
