function Get-LabDomainConfig {
    <#
    .SYNOPSIS
        Gets domain configuration for SimpleLab.

    .DESCRIPTION
        Retrieves domain configuration from config.json or returns defaults.
        Provides domain name, NetBIOS name, and safe mode password settings.

    .OUTPUTS
        PSCustomObject with DomainName, NetBIOSName, SafeModePassword, and DnsServerAddress.

    .EXAMPLE
        $config = Get-LabDomainConfig
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Initialize default domain configuration
        $defaultDomainConfig = [PSCustomObject]@{
            DomainName = "simplelab.local"
            NetBIOSName = "SIMPLELAB"
            SafeModePassword = "SimpleLab123!"
            DnsServerAddress = $null
        }

        # Get lab configuration
        $labConfig = Get-LabConfig

        # If no config exists, return defaults
        if ($null -eq $labConfig) {
            return $defaultDomainConfig
        }

        # Get network config for DC IP address
        $networkConfig = Get-LabNetworkConfig
        if ($null -ne $networkConfig -and $networkConfig.VMIPs.dc1) {
            $defaultDomainConfig.DnsServerAddress = $networkConfig.VMIPs.dc1
        }

        # Check if DomainConfiguration section exists
        if ($labConfig.PSObject.Properties.Name -contains 'DomainConfiguration') {
            $domainConfig = $labConfig.DomainConfiguration

            # Build result object with overrides
            $result = [PSCustomObject]@{
                DomainName = if ($domainConfig.PSObject.Properties.Name -contains 'DomainName') {
                    $domainConfig.DomainName
                }
                else {
                    $defaultDomainConfig.DomainName
                }
                NetBIOSName = if ($domainConfig.PSObject.Properties.Name -contains 'NetBIOSName') {
                    $domainConfig.NetBIOSName
                }
                else {
                    $defaultDomainConfig.NetBIOSName
                }
                SafeModePassword = if ($domainConfig.PSObject.Properties.Name -contains 'SafeModePassword') {
                    $domainConfig.SafeModePassword
                }
                else {
                    $defaultDomainConfig.SafeModePassword
                }
                DnsServerAddress = $defaultDomainConfig.DnsServerAddress
            }

            return $result
        }

        # Return defaults if DomainConfiguration section doesn't exist
        return $defaultDomainConfig
    }
    catch {
        throw "Get-LabDomainConfig: failed to build domain configuration - $_"
    }
}
