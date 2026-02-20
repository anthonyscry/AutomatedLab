function New-LabNAT {
    <#
    .SYNOPSIS
        Creates a NAT network configuration for the lab.

    .DESCRIPTION
        Creates an Internal vSwitch with host gateway IP and NAT configuration
        for lab VMs to have Internet access. This is an alternative to the
        simple internal switch created by New-LabSwitch. All parameters default
        to values from the lab network configuration when available.

    .PARAMETER SwitchName
        Name of the Hyper-V internal virtual switch to create or reuse.
        Defaults to the SwitchName from network config, or "SimpleLab".

    .PARAMETER GatewayIP
        IPv4 address to assign to the host adapter as the lab gateway.
        Defaults to HostGatewayIP from network config, or "10.0.0.1".

    .PARAMETER AddressSpace
        CIDR notation address space for the NAT (e.g. "10.0.0.0/24").
        Defaults to AddressSpace from network config, or "10.0.0.0/24".

    .PARAMETER NatName
        Name for the Windows NAT object. Defaults to "${SwitchName}NAT".

    .PARAMETER Force
        Remove and recreate an existing switch or NAT if the configuration
        does not match. Without -Force, mismatches return a failure result.

    .EXAMPLE
        New-LabNAT
        Creates the lab NAT using all defaults from network configuration.

    .EXAMPLE
        New-LabNAT -SwitchName "LabNAT" -GatewayIP "192.168.100.1"
        Creates a NAT switch named LabNAT with a custom gateway IP.

    .EXAMPLE
        New-LabNAT -Force
        Recreates the NAT and switch even if they already exist.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SwitchName,

        [Parameter()]
        [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
        [string]$GatewayIP,

        [Parameter()]
        [string]$AddressSpace = "255.255.255.0",

        [Parameter()]
        [string]$NatName,

        [Parameter()]
        [switch]$Force
    )

    try {
        # Get lab configuration
        $labConfig = Get-LabConfig
        $networkConfig = Get-LabNetworkConfig

        # Use config values or defaults
        $SwitchName = if ($SwitchName) {
            $SwitchName
        } elseif ($networkConfig.PSObject.Properties.Name -contains 'SwitchName') {
            $networkConfig.SwitchName
        } else {
            "SimpleLab"
        }

        $GatewayIP = if ($GatewayIP) {
            $GatewayIP
        } elseif ($networkConfig.PSObject.Properties.Name -contains 'HostGatewayIP') {
            $networkConfig.HostGatewayIP
        } else {
            "10.0.0.1"
        }

        $NatName = if ($NatName) {
            $NatName
        } elseif ($networkConfig.PSObject.Properties.Name -contains 'NATName') {
            $networkConfig.NATName
        } else {
            "${SwitchName}NAT"
        }

        $AddressSpace = if ($networkConfig.PSObject.Properties.Name -contains 'AddressSpace') {
            $networkConfig.AddressSpace
        } else {
            "10.0.0.0/24"
        }

        # Prefix length from address space
        $prefixLength = if ($AddressSpace -match '/(\d+)') {
            [int]$Matches[1]
        } else {
            24
        }

        # Validate prefix length
        if ($prefixLength -lt 1 -or $prefixLength -gt 32) {
            return [PSCustomObject]@{
                OverallStatus = 'Failed'
                Message = "Invalid CIDR prefix length '$prefixLength' in AddressSpace '$AddressSpace'. Must be 1-32."
                SwitchCreated = $false
                GatewayConfigured = $false
                NATCreated = $false
            }
        }

        $results = @{
            SwitchCreated = $false
            GatewayConfigured = $false
            NATCreated = $false
            SwitchName = $SwitchName
            GatewayIP = $GatewayIP
            NatName = $NatName
        }

        # Check for Hyper-V module
        if (-not (Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                OverallStatus = 'Failed'
                Message = "Hyper-V module not available. Install Hyper-V feature."
                SwitchCreated = $false
                GatewayConfigured = $false
                NATCreated = $false
            }
        }

        # Create or verify vSwitch
        $existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
        if ($existingSwitch) {
            if ($existingSwitch.SwitchType -ne 'Internal') {
                if ($Force) {
                    Remove-VMSwitch -Name $SwitchName -Force -ErrorAction SilentlyContinue
                    $switchRemovalDeadline = [datetime]::Now.AddSeconds(10)
                    while ([datetime]::Now -lt $switchRemovalDeadline) {
                        $switchCheck = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
                        if (-not $switchCheck) { break }
                        Start-Sleep -Seconds 1
                    }
                    if (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue) {
                        throw "Failed to remove non-internal switch '$SwitchName' before recreation."
                    }
                } else {
                    return [PSCustomObject]@{
                        OverallStatus = 'Failed'
                        Message = "Switch '$SwitchName' exists but is not Internal type. Use -Force to recreate."
                        SwitchCreated = $false
                        GatewayConfigured = $false
                        NATCreated = $false
                    }
                }
            } else {
                Write-LabStatus -Status OK -Message "VMSwitch exists: $SwitchName" -Indent 0
                $results.SwitchCreated = $true
            }
        }

        if (-not $results.SwitchCreated) {
            $null = New-VMSwitch -Name $SwitchName -SwitchType Internal
            Write-LabStatus -Status OK -Message "Created VMSwitch: $SwitchName (Internal)" -Indent 0
            $results.SwitchCreated = $true
        }

        # Configure gateway IP on host
        $ifAlias = "vEthernet ($SwitchName)"
        $existingGateway = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                          Where-Object { $_.IPAddress -eq $GatewayIP }

        if (-not $existingGateway) {
            # Remove existing IPs on interface
            Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

            # Add gateway IP
            $null = New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIP -PrefixLength $prefixLength
            Write-LabStatus -Status OK -Message "Set host gateway IP: $GatewayIP on $ifAlias" -Indent 0
            $results.GatewayConfigured = $true
        } else {
            Write-LabStatus -Status OK -Message "Host gateway IP already set: $GatewayIP" -Indent 0
            $results.GatewayConfigured = $true
        }

        # Create or verify NAT
        $existingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
        if ($existingNat) {
            if ($existingNat.InternalIPInterfaceAddressPrefix -ne $AddressSpace) {
                if ($Force) {
                    $null = Remove-NetNat -Name $NatName -Confirm:$false
                    $natRemovalDeadline = [datetime]::Now.AddSeconds(10)
                    while ([datetime]::Now -lt $natRemovalDeadline) {
                        $natCheck = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
                        if (-not $natCheck) { break }
                        Start-Sleep -Seconds 1
                    }
                    if (Get-NetNat -Name $NatName -ErrorAction SilentlyContinue) {
                        throw "Failed to remove NAT '$NatName' before recreation."
                    }
                } else {
                    return [PSCustomObject]@{
                        OverallStatus = 'Partial'
                        Message = "NAT '$NatName' exists with different prefix. Use -Force to recreate."
                        SwitchCreated = $results.SwitchCreated
                        GatewayConfigured = $results.GatewayConfigured
                        NATCreated = $false
                    }
                }
            } else {
                Write-LabStatus -Status OK -Message "NAT exists: $NatName" -Indent 0
                $results.NATCreated = $true
            }
        }

        if (-not $results.NATCreated) {
            $null = New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace
            Write-LabStatus -Status OK -Message "Created NAT: $NatName for $AddressSpace" -Indent 0
            $results.NATCreated = $true
        }

        # Update network config to track NAT mode
        if ($labConfig) {
            if ($labConfig.PSObject.Properties.Name -contains 'LabSettings') {
                $labConfig.LabSettings | Add-Member -NotePropertyName 'EnableNAT' -NotePropertyValue $true -Force
            }
        }

        $overallStatus = if ($results.SwitchCreated -and $results.GatewayConfigured -and $results.NATCreated) {
            'OK'
        } else {
            'Partial'
        }

        return [PSCustomObject]@{
            OverallStatus = $overallStatus
            Message = "NAT network configuration complete"
            SwitchName = $SwitchName
            GatewayIP = $GatewayIP
            NatName = $NatName
            AddressSpace = $AddressSpace
            SwitchCreated = $results.SwitchCreated
            GatewayConfigured = $results.GatewayConfigured
            NATCreated = $results.NATCreated
        }
    }
    catch {
        throw "New-LabNAT: failed to create NAT configuration - $_"
    }
}
