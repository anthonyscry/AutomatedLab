function Invoke-LabGatewayForwarding {
    <#
    .SYNOPSIS
        Enables IP forwarding on a gateway VM via PowerShell Direct.
        Isolated in its own function so tests can mock it without dealing
        with Invoke-Command's complex parameter sets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName
    )
    $scriptBlock = {
        Get-NetIPInterface | Where-Object { $_.AddressFamily -eq 'IPv4' } | ForEach-Object {
            Set-NetIPInterface -InterfaceIndex $_.InterfaceIndex -Forwarding Enabled -ErrorAction SilentlyContinue
        }
    }
    Invoke-Command -VMName $VMName -ScriptBlock $scriptBlock -ErrorAction Stop
}

function Initialize-LabNetwork {
    <#
    .SYNOPSIS
        Configures static IP addresses and network adapters for lab virtual machines.

    .DESCRIPTION
        Configures static IP addresses for all specified lab VMs using the
        network configuration. Supports multi-subnet scenarios where VMs are
        assigned to different named Hyper-V switches with optional VLAN tagging.

        For each VM, the function:
        1. Looks up the VM's switch/VLAN/IP assignment from Get-LabNetworkConfig.
        2. Calls New-LabVMNetworkAdapter to connect the adapter to the correct switch.
        3. Calls Set-VMStaticIP to configure the static IP inside the VM.

        When Routing.Mode is 'host', adds static routes on the Hyper-V host between
        switch subnets so cross-subnet traffic is routed via the vEthernet adapters.

        When Routing.Mode is 'gateway', enables IP forwarding on the gateway VM via
        PowerShell Direct.

        Backward compatible: single-subnet configs without switch assignments use the
        existing flow unchanged.

    .PARAMETER VMNames
        Array of VM names to configure. Defaults to @("dc1", "svr1", "ws1").

    .OUTPUTS
        PSCustomObject with VMConfigured hashtable, FailedVMs array,
        OverallStatus, Duration, and Message.

    .EXAMPLE
        Initialize-LabNetwork
        Configures default VMs with IPs and switch assignments from network config.

    .EXAMPLE
        Initialize-LabNetwork -VMNames @("dc1", "ws1")
        Configures only dc1 and ws1.

    .EXAMPLE
        (Initialize-LabNetwork).OverallStatus
        Returns "OK", "Partial", or "Failed".
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$VMNames = @("dc1", "svr1", "ws1")
    )

    try {
        # Start timing
        $startTime = Get-Date

        # Initialize result object
        $result = [PSCustomObject]@{
            VMConfigured  = @{}
            FailedVMs     = @()
            OverallStatus = 'Failed'
            Duration      = $null
            Message       = ''
        }

        # Get network configuration
        $networkConfig = Get-LabNetworkConfig

        if ($null -eq $networkConfig) {
            $result.Message       = 'Failed to retrieve network configuration'
            $result.OverallStatus = 'Failed'
            $result.Duration      = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Determine if per-VM switch assignments are available
        $hasAssignments = ($null -ne $networkConfig.VMAssignments) -and ($networkConfig.VMAssignments.Count -gt 0)

        # Determine if multi-switch routing should run (2+ switches configured)
        $switches = $networkConfig.Switches
        $isMultiSwitch = ($null -ne $switches) -and ($switches.Count -gt 1)

        # Track success and failure counts
        $successCount = 0
        $failureCount = 0

        # Configure each VM
        foreach ($vmName in $VMNames) {
            $ipAddress   = $null
            $switchName  = $null
            $vlanId      = 0
            $prefixLen   = if ($null -ne $networkConfig.PrefixLength) { $networkConfig.PrefixLength } else { 24 }

            if ($hasAssignments -and $networkConfig.VMAssignments.ContainsKey($vmName)) {
                $assignment = $networkConfig.VMAssignments[$vmName]
                $ipAddress  = $assignment.IP
                $switchName = $assignment.Switch
                $vlanId     = if ($null -ne $assignment.VlanId) { $assignment.VlanId } else { 0 }
                $prefixLen  = if ($null -ne $assignment.PrefixLength) { $assignment.PrefixLength } else { $prefixLen }
            }
            else {
                # Backward compat: fall back to VMIPs flat hashtable
                $vmips     = $networkConfig.VMIPs
                $ipAddress = $vmips.$vmName
            }

            if ([string]::IsNullOrEmpty($ipAddress)) {
                $result.FailedVMs      += $vmName
                $result.VMConfigured[$vmName] = [PSCustomObject]@{
                    VMName    = $vmName
                    IPAddress = 'Not configured'
                    Configured = $false
                    Status    = 'Failed'
                    Message   = "No IP address configured for VM '$vmName' in network configuration"
                }
                $failureCount++
                continue
            }

            # Step 1: Connect VM adapter to named switch (if switch assignment is available)
            if (-not [string]::IsNullOrWhiteSpace($switchName)) {
                $adapterParams = @{
                    VMName     = $vmName
                    SwitchName = $switchName
                }
                if ($vlanId -gt 0) {
                    $adapterParams['VlanId'] = $vlanId
                }
                $adapterResult = New-LabVMNetworkAdapter @adapterParams
                if ($adapterResult.Status -ne 'OK') {
                    Write-Verbose "Initialize-LabNetwork: adapter config warning for '$vmName': $($adapterResult.Message)"
                }
            }

            # Step 2: Configure static IP inside the VM
            $vmResult = Set-VMStaticIP -VMName $vmName -IPAddress $ipAddress -PrefixLength $prefixLen

            # Store result
            $result.VMConfigured[$vmName] = $vmResult

            if ($vmResult.Status -eq 'OK') {
                $successCount++
            }
            else {
                $failureCount++
                $result.FailedVMs += $vmName
            }
        }

        # Step 3: Configure inter-subnet routing (only for multi-switch configs)
        if ($isMultiSwitch) {
            $routing = $networkConfig.Routing

            if ($null -ne $routing -and $routing.Mode -eq 'host') {
                # Add static routes on the Hyper-V host between each pair of subnets
                # Each switch's subnet is reachable via its GatewayIp on the vEthernet adapter
                for ($i = 0; $i -lt $switches.Count; $i++) {
                    $sw = $switches[$i]
                    $destPrefix = $sw.AddressSpace
                    $nextHop    = $sw.GatewayIp
                    $ifAlias    = "vEthernet ($($sw.Name))"

                    try {
                        $existing = Get-NetRoute -DestinationPrefix $destPrefix -ErrorAction SilentlyContinue
                        if ($null -eq $existing -or @($existing).Count -eq 0) {
                            New-NetRoute -DestinationPrefix $destPrefix -InterfaceAlias $ifAlias -NextHop $nextHop -RouteMetric 10 -ErrorAction Stop
                        }
                    }
                    catch {
                        Write-Verbose "Initialize-LabNetwork: could not add route for $destPrefix - $_"
                    }
                }
            }
            elseif ($null -ne $routing -and $routing.Mode -eq 'gateway' -and -not [string]::IsNullOrWhiteSpace($routing.GatewayVM)) {
                # Enable IP forwarding on the gateway VM via PowerShell Direct
                $gwVM = $routing.GatewayVM
                try {
                    Invoke-LabGatewayForwarding -VMName $gwVM
                }
                catch {
                    Write-Verbose "Initialize-LabNetwork: could not enable forwarding on '$gwVM' - $_"
                }
            }
        }

        # Calculate duration
        $result.Duration = New-TimeSpan -Start $startTime -End (Get-Date)

        # Determine overall status
        if ($failureCount -eq 0) {
            $result.OverallStatus = 'OK'
            $result.Message       = "Successfully configured $successCount VM(s)"
        }
        elseif ($successCount -eq 0) {
            $result.OverallStatus = 'Failed'
            $result.Message       = 'Failed to configure all VMs'
        }
        else {
            $result.OverallStatus = 'Partial'
            $result.Message       = "Configured $successCount VM(s), failed $failureCount VM(s)"
        }

        return $result
    }
    catch {
        throw "Initialize-LabNetwork: failed to configure lab network - $_"
    }
}
