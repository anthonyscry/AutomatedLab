function Test-LabDNS {
    <#
    .SYNOPSIS
        Tests DNS server health and functionality.

    .DESCRIPTION
        Validates DNS service status, query response, forwarder configuration,
        and name resolution capabilities. Uses PowerShell Direct for in-VM checks.

    .PARAMETER VMName
        Name of the domain controller VM to test (default: "dc1").

    .PARAMETER TestInternetResolution
        Test Internet name resolution through forwarders.

    .OUTPUTS
        PSCustomObject with DNS health status and diagnostic information.

    .EXAMPLE
        Test-LabDNS

    .EXAMPLE
        Test-LabDNS -TestInternetResolution
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$VMName = "dc1",

        [Parameter()]
        [switch]$TestInternetResolution
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        DNSRunning = $false
        DNSResponding = $false
        ForwardersConfigured = $false
        InternalResolution = $false
        InternetResolution = $false
        OverallStatus = "Failed"
        Message = ""
        Checks = @()
        Duration = $null
    }

    try {
        # Check 1: Hyper-V module available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.OverallStatus = "Failed"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Check 2: VM exists and is running
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.OverallStatus = "Failed"
            $result.Message = "VM '$VMName' does not exist"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        if ($vm.State -ne "Running") {
            $result.OverallStatus = "Failed"
            $result.Message = "VM '$VMName' is not running (State: $($vm.State))"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        $result.Checks += [PSCustomObject]@{
            Name = "VMState"
            Status = "Pass"
            Message = "VM is running"
        }

        # Run DNS checks inside the VM via PowerShell Direct
        try {
            $dnsChecks = Invoke-Command -VMName $VMName -ScriptBlock {
                param($testInternet)

                $checks = @()
                $dnsRunning = $false
                $dnsResponding = $false
                $forwardersConfigured = $false
                $internalResolution = $false
                $internetResolution = $false

                # Check 3: DNS service is running
                $dnsService = Get-Service -Name DNS -ErrorAction SilentlyContinue
                if ($dnsService -and $dnsService.Status -eq "Running") {
                    $dnsRunning = $true
                    $checks += [PSCustomObject]@{
                        Name = "DNSService"
                        Status = "Pass"
                        Message = "DNS service is running"
                    }
                }
                else {
                    $checks += [PSCustomObject]@{
                        Name = "DNSService"
                        Status = "Fail"
                        Message = "DNS service is not running"
                    }
                }

                # Check 4: DNS server is responding to queries
                if ($dnsRunning) {
                    try {
                        $dnsTest = Test-DnsServerDnsServer -ComputerName localhost -ErrorAction Stop
                        if ($dnsTest) {
                            $dnsResponding = $true
                            $checks += [PSCustomObject]@{
                                Name = "DNSResponding"
                                Status = "Pass"
                                Message = "DNS server is responding to queries"
                            }
                        }
                    }
                    catch {
                        $checks += [PSCustomObject]@{
                            Name = "DNSResponding"
                            Status = "Fail"
                            Message = "DNS server not responding: $($_.Exception.Message)"
                        }
                    }
                }

                # Check 5: Forwarders are configured
                if ($dnsRunning) {
                    try {
                        $forwarders = Get-DnsServerForwarder -ErrorAction SilentlyContinue
                        if ($forwarders -and $forwarders.IPAddress.Count -gt 0) {
                            $forwardersConfigured = $true
                            $forwarderList = $forwarders.IPAddress -join ", "
                            $checks += [PSCustomObject]@{
                                Name = "Forwarders"
                                Status = "Pass"
                                Message = "Forwarders configured: $forwarderList"
                            }
                        }
                        else {
                            $checks += [PSCustomObject]@{
                                Name = "Forwarders"
                                Status = "Warning"
                                Message = "No forwarders configured - Internet resolution may not work"
                            }
                        }
                    }
                    catch {
                        $checks += [PSCustomObject]@{
                            Name = "Forwarders"
                            Status = "Warning"
                            Message = "Could not check forwarders: $($_.Exception.Message)"
                        }
                    }
                }

                # Check 6: Can resolve localhost (internal resolution test)
                if ($dnsRunning) {
                    try {
                        $localResolve = Resolve-DnsName -Name localhost -ErrorAction SilentlyContinue
                        if ($localResolve) {
                            $internalResolution = $true
                            $checks += [PSCustomObject]@{
                                Name = "InternalResolution"
                                Status = "Pass"
                                Message = "Internal DNS resolution working"
                            }
                        }
                    }
                    catch {
                        $checks += [PSCustomObject]@{
                            Name = "InternalResolution"
                            Status = "Warning"
                            Message = "Internal resolution test failed: $($_.Exception.Message)"
                        }
                    }
                }

                # Check 7: Internet resolution (if requested)
                if ($testInternet -and $dnsRunning) {
                    try {
                        # Test with a well-known public DNS name
                        $internetResolve = Resolve-DnsName -Name "google.com" -ErrorAction SilentlyContinue
                        if ($internetResolve) {
                            $internetResolution = $true
                            $checks += [PSCustomObject]@{
                                Name = "InternetResolution"
                                Status = "Pass"
                                Message = "Internet DNS resolution working"
                            }
                        }
                        else {
                            $checks += [PSCustomObject]@{
                                Name = "InternetResolution"
                                Status = "Fail"
                                Message = "Cannot resolve Internet names (check forwarders)"
                            }
                        }
                    }
                    catch {
                        $checks += [PSCustomObject]@{
                            Name = "InternetResolution"
                            Status = "Fail"
                            Message = "Internet resolution failed: $($_.Exception.Message)"
                        }
                    }
                }

                # Return results
                return @{
                    DNSRunning = $dnsRunning
                    DNSResponding = $dnsResponding
                    ForwardersConfigured = $forwardersConfigured
                    InternalResolution = $internalResolution
                    InternetResolution = $internetResolution
                    Checks = $checks
                }
            } -ArgumentList $TestInternetResolution -ErrorAction Stop

            # Map results from VM
            $result.DNSRunning = $dnsChecks.DNSRunning
            $result.DNSResponding = $dnsChecks.DNSResponding
            $result.ForwardersConfigured = $dnsChecks.ForwardersConfigured
            $result.InternalResolution = $dnsChecks.InternalResolution
            $result.InternetResolution = $dnsChecks.InternetResolution
            $result.Checks += $dnsChecks.Checks

            # Determine overall status
            $failCount = ($dnsChecks.Checks | Where-Object { $_.Status -eq "Fail" }).Count
            $warningCount = ($dnsChecks.Checks | Where-Object { $_.Status -eq "Warning" }).Count

            if ($failCount -eq 0 -and $warningCount -eq 0) {
                $result.OverallStatus = "Healthy"
                $result.Message = "DNS is fully functional"
            }
            elseif ($failCount -eq 0) {
                $result.OverallStatus = "Warning"
                $result.Message = "DNS is functional with $warningCount warning(s)"
            }
            else {
                $result.OverallStatus = "Failed"
                $result.Message = "DNS has $failCount error(s)"
            }

            if (-not $result.DNSRunning) {
                $result.OverallStatus = "Failed"
                $result.Message = "DNS service is not running - VM may not be a domain controller"
            }
        }
        catch {
            $result.OverallStatus = "Error"
            $result.Message = "PowerShell Direct connection failed: $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
    catch {
        $result.OverallStatus = "Error"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
