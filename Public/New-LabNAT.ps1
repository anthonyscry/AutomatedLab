function New-LabNAT {
    <#
    .SYNOPSIS
        Creates a NAT network configuration for the lab.

    .DESCRIPTION
        Creates an Internal vSwitch with host gateway IP and NAT configuration
        for lab VMs to have Internet access. This is an alternative to the
        simple internal switch created by New-LabSwitch.

    .EXAMPLE
        New-LabNAT

    .EXAMPLE
        New-LabNAT -SwitchName "LabNAT" -GatewayIP "192.168.100.1"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SwitchName,

        [Parameter()]
        [string]$GatewayIP,

        [Parameter()]
        [string]$AddressSpace = "255.255.255.0",

        [Parameter()]
        [string]$NatName,

        [Parameter()]
        [switch]$Force
    )

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
                Start-Sleep -Seconds 1
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
            Write-Host "[OK] VMSwitch exists: $SwitchName" -ForegroundColor Green
            $results.SwitchCreated = $true
        }
    }

    if (-not $results.SwitchCreated) {
        New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
        Write-Host "[OK] Created VMSwitch: $SwitchName (Internal)" -ForegroundColor Green
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
        New-NetIPAddress -InterfaceAlias $ifAlias -IPAddress $GatewayIP -PrefixLength $prefixLength | Out-Null
        Write-Host "[OK] Set host gateway IP: $GatewayIP on $ifAlias" -ForegroundColor Green
        $results.GatewayConfigured = $true
    } else {
        Write-Host "[OK] Host gateway IP already set: $GatewayIP" -ForegroundColor Green
        $results.GatewayConfigured = $true
    }

    # Create or verify NAT
    $existingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
    if ($existingNat) {
        if ($existingNat.InternalIPInterfaceAddressPrefix -ne $AddressSpace) {
            if ($Force) {
                Remove-NetNat -Name $NatName -Confirm:$false | Out-Null
                Start-Sleep -Seconds 1
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
            Write-Host "[OK] NAT exists: $NatName" -ForegroundColor Green
            $results.NATCreated = $true
        }
    }

    if (-not $results.NATCreated) {
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $AddressSpace | Out-Null
        Write-Host "[OK] Created NAT: $NatName for $AddressSpace" -ForegroundColor Green
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
