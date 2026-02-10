function Initialize-LabNetwork {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$VMNames = @("SimpleDC", "SimpleServer", "SimpleWin11")
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMConfigured = @{}
        FailedVMs = @()
        OverallStatus = "Failed"
        Duration = $null
        Message = ""
    }

    # Get network configuration
    $networkConfig = Get-LabNetworkConfig

    if ($null -eq $networkConfig) {
        $result.Message = "Failed to retrieve network configuration"
        $result.OverallStatus = "Failed"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }

    # Track success and failure counts
    $successCount = 0
    $failureCount = 0

    # Configure each VM
    foreach ($vmName in $VMNames) {
        # Get the IP address for this VM from network config
        $ipAddress = $networkConfig.VMIPs[$vmName]

        if ([string]::IsNullOrEmpty($ipAddress)) {
            # No IP configured for this VM
            $result.FailedVMs += $vmName
            $result.VMConfigured[$vmName] = [PSCustomObject]@{
                VMName = $vmName
                IPAddress = "Not configured"
                Configured = $false
                Status = "Failed"
                Message = "No IP address configured for VM '$vmName' in network configuration"
            }
            $failureCount++
            continue
        }

        # Configure the VM
        $vmResult = Set-VMStaticIP -VMName $vmName -IPAddress $ipAddress -PrefixLength $networkConfig.PrefixLength

        # Store result
        $result.VMConfigured[$vmName] = $vmResult

        if ($vmResult.Status -eq "OK") {
            $successCount++
        }
        else {
            $failureCount++
            $result.FailedVMs += $vmName
        }
    }

    # Calculate duration
    $result.Duration = New-TimeSpan -Start $startTime -End (Get-Date)

    # Determine overall status
    if ($failureCount -eq 0) {
        $result.OverallStatus = "OK"
        $result.Message = "Successfully configured $successCount VM(s)"
    }
    elseif ($successCount -eq 0) {
        $result.OverallStatus = "Failed"
        $result.Message = "Failed to configure all VMs"
    }
    else {
        $result.OverallStatus = "Partial"
        $result.Message = "Configured $successCount VM(s), failed $failureCount VM(s)"
    }

    return $result
}
