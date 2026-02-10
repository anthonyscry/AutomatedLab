function Test-LabNetworkHealth {
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
        OverallStatus = "Failed"
        ConnectivityTests = @()
        FailedTests = @()
        Duration = $null
        Message = ""
    }

    # Step 1: Check vSwitch exists using Test-LabNetwork
    $vSwitchCheck = Test-LabNetwork

    if ($null -eq $vSwitchCheck -or $vSwitchCheck.Exists -eq $false) {
        $result.OverallStatus = "Failed"
        $result.Message = "SimpleLab vSwitch not found. Run New-LabSwitch first."
        $result.Duration = New-TimeSpan -Start $startTime -End (Get-Date)
        return $result
    }

    # Step 2: Get network configuration using Get-LabNetworkConfig
    $networkConfig = Get-LabNetworkConfig

    if ($null -eq $networkConfig) {
        $result.OverallStatus = "Failed"
        $result.Message = "Failed to retrieve network configuration"
        $result.Duration = New-TimeSpan -Start $startTime -End (Get-Date)
        return $result
    }

    # Step 3 & 4: Test VM-to-VM connectivity for all pairs
    $allTestsPassed = $true
    $someTestsPassed = $false
    $vmRunningCount = 0

    foreach ($sourceVM in $VMNames) {
        foreach ($targetVM in $VMNames) {
            # Skip self-pairs
            if ($sourceVM -eq $targetVM) {
                continue
            }

            # Get target IP from network config
            $targetIP = $networkConfig.VMIPs[$targetVM]

            if ([string]::IsNullOrEmpty($targetIP)) {
                # No IP configured for target VM
                $testResult = [PSCustomObject]@{
                    SourceVM = $sourceVM
                    TargetVM = $targetVM
                    TargetIP = "Not configured"
                    Reachable = $false
                    Status = "Failed"
                    Message = "No IP address configured for VM '$targetVM'"
                }
                $result.ConnectivityTests += $testResult
                $result.FailedTests += $testResult
                $allTestsPassed = $false
                continue
            }

            # Test connectivity
            $testResult = Test-VMNetworkConnectivity -SourceVM $sourceVM -TargetIP $targetIP -Count 2

            # Add TargetVM to result for clarity
            $testResult | Add-Member -MemberType NoteProperty -Name TargetVM -Value $targetVM -Force

            # Store result
            $result.ConnectivityTests += $testResult

            # Track status
            if ($testResult.Status -eq "OK") {
                $someTestsPassed = $true
                $vmRunningCount++
            }
            elseif ($testResult.Status -eq "VMNotFound") {
                # VM not running - not a test failure, but affects overall status
                $allTestsPassed = $false
            }
            else {
                # Connectivity test failed
                $result.FailedTests += $testResult
                $allTestsPassed = $false
            }
        }
    }

    # Calculate duration
    $result.Duration = New-TimeSpan -Start $startTime -End (Get-Date)

    # Determine overall status
    if ($allTestsPassed) {
        $result.OverallStatus = "OK"
        $result.Message = "All connectivity tests passed ($($result.ConnectivityTests.Count) tests)"
    }
    elseif ($someTestsPassed) {
        $result.OverallStatus = "Partial"
        $passedCount = ($result.ConnectivityTests | Where-Object { $_.Status -eq "OK" }).Count
        $failedCount = $result.FailedTests.Count
        $result.Message = "$passedCount test(s) passed, $failedCount test(s) failed"
    }
    else {
        # Check if any VMs are running
        if ($vmRunningCount -eq 0) {
            $result.OverallStatus = "Warning"
            $result.Message = "No VMs are running. Start VMs to test network connectivity."
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "All connectivity tests failed"
        }
    }

    return $result
}
