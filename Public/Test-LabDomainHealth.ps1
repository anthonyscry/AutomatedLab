function Test-LabDomainHealth {
    <#
    .SYNOPSIS
        Performs comprehensive health validation for the SimpleLab domain.

    .DESCRIPTION
        Validates domain controller, DNS, and member server health.
        Provides clear status reporting for troubleshooting.

    .PARAMETER DomainName
        Domain name to check (default: from config or "simplelab.local").

    .PARAMETER Credential
        Domain administrator credential (default: from config or prompts).

    .PARAMETER IncludeMemberServers
        Include health checks for member servers (default: true).

    .OUTPUTS
        PSCustomObject with comprehensive domain health status.

    .EXAMPLE
        Test-LabDomainHealth

    .EXAMPLE
        Test-LabDomainHealth -DomainName "simplelab.local"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$GlobalLabConfig.Lab.DomainName,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [switch]$IncludeMemberServers = $true
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        DomainName = ""
        OverallStatus = "Failed"
        Message = ""
        Checks = @()
        DCHealth = $null
        DNSHealth = $null
        MemberHealth = @()
        Duration = $null
    }

    try {
        # Get domain configuration
        $domainConfig = Get-LabDomainConfig
        $targetDomain = if ($PSBoundParameters.ContainsKey('DomainName')) {
            $GlobalLabConfig.Lab.DomainName
        }
        else {
            $domainConfig.DomainName
        }

        $result.DomainName = $targetDomain

        # Set up credential if not provided
        $targetCredential = $Credential
        if ($null -eq $targetCredential) {
            $password = ConvertTo-SecureString -String $domainConfig.SafeModePassword -AsPlainText -Force
            $targetCredential = New-Object System.Management.Automation.PSCredential ("$($targetDomain)\Administrator", $password)
        }

        Write-Verbose "Starting domain health validation for '$targetDomain'..."

        #region DC Connectivity Checks
        # === Check 1: Domain Controller Health ===
        Write-Verbose "Checking domain controller health..."

        $dcHealth = [PSCustomObject]@{
            VMName = "dc1"
            Running = $false
            Accessible = $false
            ADDSServiceRunning = $false
            DomainReachable = $false
            Status = "Failed"
            Message = ""
            Checks = @()
        }

        # Check DC VM exists and is running
        $dcVM = Get-VM -Name "dc1" -ErrorAction SilentlyContinue
        if ($null -eq $dcVM) {
            $dcHealth.Status = "NotFound"
            $dcHealth.Message = "Domain controller VM 'dc1' not found"
            $result.Checks += [PSCustomObject]@{
                Name = "DC_VMExists"
                Status = "Fail"
                Message = "Domain controller VM does not exist - run Initialize-LabVMs first"
            }
        }
        elseif ($dcVM.State -ne "Running") {
            $dcHealth.Status = "NotRunning"
            $dcHealth.Message = "Domain controller VM is not running (State: $($dcVM.State))"
            $result.Checks += [PSCustomObject]@{
                Name = "DC_VMRunning"
                Status = "Fail"
                Message = "Domain controller VM not running - run Start-LabVMs first"
            }
        }
        else {
            $dcHealth.Running = $true
            $dcHealth.Checks += [PSCustomObject]@{
                Name = "DC_VMRunning"
                Status = "Pass"
                Message = "Domain controller VM is running"
            }

            # Check DC is accessible via PowerShell Direct
            try {
                $accessible = Invoke-Command -VMName "dc1" -ScriptBlock {
                    $true
                } -ErrorAction SilentlyContinue

                if ($null -ne $accessible) {
                    $dcHealth.Accessible = $true
                    $dcHealth.Checks += [PSCustomObject]@{
                        Name = "DC_Accessible"
                        Status = "Pass"
                        Message = "Domain controller is accessible via PowerShell Direct"
                    }

                    #region AD DS Service Validation
                    # Check AD DS service
                    try {
                        $addsdService = Invoke-Command -VMName "dc1" -ScriptBlock {
                            $service = Get-Service -Name NTDS -ErrorAction SilentlyContinue
                            return $service.Status -eq "Running"
                        } -ErrorAction SilentlyContinue

                        if ($addsdService) {
                            $dcHealth.ADDSServiceRunning = $true
                            $dcHealth.Checks += [PSCustomObject]@{
                                Name = "DC_ADDSService"
                                Status = "Pass"
                                Message = "AD DS service is running"
                            }
                        }
                        else {
                            $dcHealth.Checks += [PSCustomObject]@{
                                Name = "DC_ADDSService"
                                Status = "Fail"
                                Message = "AD DS service is not running"
                            }
                        }
                    }
                    catch {
                        $dcHealth.Checks += [PSCustomObject]@{
                            Name = "DC_ADDSService"
                            Status = "Error"
                            Message = "Failed to check AD DS service: $($_.Exception.Message)"
                        }
                    }

                    # Check domain is reachable
                    try {
                        $domainCheck = Invoke-Command -VMName "dc1" -ScriptBlock {
                            param($domainName)
                            Get-ADDomain -Identity $domainName -ErrorAction SilentlyContinue
                        } -ArgumentList $targetDomain -ErrorAction SilentlyContinue

                        if ($null -ne $domainCheck) {
                            $dcHealth.DomainReachable = $true
                            $dcHealth.Checks += [PSCustomObject]@{
                                Name = "DC_DomainReachable"
                                Status = "Pass"
                                Message = "Domain '$targetDomain' is reachable and responding"
                            }
                        }
                        else {
                            $dcHealth.Checks += [PSCustomObject]@{
                                Name = "DC_DomainReachable"
                                Status = "Fail"
                                Message = "Domain '$targetDomain' is not reachable - DC may not be promoted yet"
                            }
                        }
                    }
                    catch {
                        $dcHealth.Checks += [PSCustomObject]@{
                            Name = "DC_DomainReachable"
                            Status = "Error"
                            Message = "Domain check failed: $($_.Exception.Message)"
                        }
                    }

                    # Determine DC health status
                    $dcFailures = ($dcHealth.Checks | Where-Object { $_.Status -eq "Fail" }).Count
                    $dcErrors = ($dcHealth.Checks | Where-Object { $_.Status -eq "Error" }).Count

                    if ($dcFailures -eq 0 -and $dcErrors -eq 0) {
                        $dcHealth.Status = "Healthy"
                        $dcHealth.Message = "Domain controller is healthy"
                    }
                    elseif ($dcFailures -eq 0) {
                        $dcHealth.Status = "Warning"
                        $dcHealth.Message = "Domain controller has $dcErrors error(s)"
                    }
                    else {
                        $dcHealth.Status = "Failed"
                        $dcHealth.Message = "Domain controller has $dcFailures failure(s)"
                    }
                }
                else {
                    $dcHealth.Checks += [PSCustomObject]@{
                        Name = "DC_Accessible"
                        Status = "Fail"
                        Message = "Cannot connect to domain controller via PowerShell Direct"
                    }
                }
            }
            catch {
                $dcHealth.Checks += [PSCustomObject]@{
                    Name = "DC_Accessible"
                    Status = "Error"
                    Message = "PowerShell Direct error: $($_.Exception.Message)"
                }
            }
        }

        $result.DCHealth = $dcHealth
        $result.Checks += [PSCustomObject]@{
            Name = "DC_Overall"
            Status = $dcHealth.Status
            Message = $dcHealth.Message
        }
        #endregion AD DS Service Validation
        #endregion DC Connectivity Checks

        #region DNS Validation
        # === Check 2: DNS Health ===
        Write-Verbose "Checking DNS health..."

        $dnsHealth = [PSCustomObject]@{
            ServiceRunning = $false
            Responding = $false
            ForwardersConfigured = $false
            CanResolveDomain = $false
            Status = "Failed"
            Message = ""
            Checks = @()
        }

        if ($dcHealth.Running -and $dcHealth.Accessible) {
            # Run DNS checks from DC
            try {
                $dnsChecks = Invoke-Command -VMName "dc1" -ScriptBlock {
                    $checks = @()
                    $serviceRunning = $false
                    $responding = $false
                    $forwardersConfigured = $false
                    $canResolve = $false

                    # Check DNS service
                    $dnsService = Get-Service -Name DNS -ErrorAction SilentlyContinue
                    if ($dnsService -and $dnsService.Status -eq "Running") {
                        $serviceRunning = $true
                        $checks += [PSCustomObject]@{
                            Name = "DNS_Service"
                            Status = "Pass"
                            Message = "DNS service is running"
                        }
                    }
                    else {
                        $checks += [PSCustomObject]@{
                            Name = "DNS_Service"
                            Status = "Fail"
                            Message = "DNS service is not running"
                        }
                    }

                    if ($serviceRunning) {
                        # Check DNS is responding
                        try {
                            $dnsTest = Test-DnsServerDnsServer -ErrorAction SilentlyContinue
                            if ($null -ne $dnsTest) {
                                $responding = $true
                                $checks += [PSCustomObject]@{
                                    Name = "DNS_Responding"
                                    Status = "Pass"
                                    Message = "DNS server is responding to queries"
                                }
                            }
                        }
                        catch {
                            $checks += [PSCustomObject]@{
                                Name = "DNS_Responding"
                                Status = "Fail"
                                Message = "DNS server not responding: $($_.Exception.Message)"
                            }
                        }

                        # Check forwarders
                        try {
                            $forwarders = Get-DnsServerForwarder -ErrorAction SilentlyContinue
                            if ($forwarders -and $forwarders.IPAddress.Count -gt 0) {
                                $forwardersConfigured = $true
                                $forwarderList = $forwarders.IPAddress -join ", "
                                $checks += [PSCustomObject]@{
                                    Name = "DNS_Forwarders"
                                    Status = "Pass"
                                    Message = "Forwarders configured: $forwarderList"
                                }
                            }
                            else {
                                $checks += [PSCustomObject]@{
                                    Name = "DNS_Forwarders"
                                    Status = "Warning"
                                    Message = "No forwarders configured - Internet resolution may not work"
                                }
                            }
                        }
                        catch {
                            $checks += [PSCustomObject]@{
                                Name = "DNS_Forwarders"
                                Status = "Warning"
                                Message = "Could not check forwarders: $($_.Exception.Message)"
                            }
                        }

                        # Check domain name resolution
                        try {
                            $resolveTest = Resolve-DnsName -Name $targetDomain -ErrorAction SilentlyContinue
                            if ($resolveTest) {
                                $canResolve = $true
                                $checks += [PSCustomObject]@{
                                    Name = "DNS_Resolution"
                                    Status = "Pass"
                                    Message = "Can resolve domain name '$targetDomain'"
                                }
                            }
                        }
                        catch {
                            $checks += [PSCustomObject]@{
                                Name = "DNS_Resolution"
                                Status = "Warning"
                                Message = "Domain resolution test failed: $($_.Exception.Message)"
                            }
                        }
                    }

                    return @{
                        ServiceRunning = $serviceRunning
                        Responding = $responding
                        ForwardersConfigured = $forwardersConfigured
                        CanResolveDomain = $canResolve
                        Checks = $checks
                    }
                } -ErrorAction SilentlyContinue

                if ($dnsChecks) {
                    $dnsHealth.ServiceRunning = $dnsChecks.ServiceRunning
                    $dnsHealth.Responding = $dnsChecks.Responding
                    $dnsHealth.ForwardersConfigured = $dnsChecks.ForwardersConfigured
                    $dnsHealth.CanResolveDomain = $dnsChecks.CanResolveDomain
                    $dnsHealth.Checks += $dnsChecks.Checks

                    # Determine DNS health status
                    $dnsFailures = ($dnsChecks.Checks | Where-Object { $_.Status -eq "Fail" }).Count
                    $dnsWarnings = ($dnsChecks.Checks | Where-Object { $_.Status -eq "Warning" }).Count

                    if ($dnsFailures -eq 0 -and $dnsWarnings -eq 0) {
                        $dnsHealth.Status = "Healthy"
                        $dnsHealth.Message = "DNS is fully functional"
                    }
                    elseif ($dnsFailures -eq 0) {
                        $dnsHealth.Status = "Warning"
                        $dnsHealth.Message = "DNS is functional with $dnsWarnings warning(s)"
                    }
                    else {
                        $dnsHealth.Status = "Failed"
                        $dnsHealth.Message = "DNS has $dnsFailures failure(s)"
                    }
                }
            }
            catch {
                $dnsHealth.Checks += [PSCustomObject]@{
                    Name = "DNS_CheckError"
                    Status = "Error"
                    Message = "DNS health check failed: $($_.Exception.Message)"
                }
                $dnsHealth.Status = "Error"
                $dnsHealth.Message = "Could not complete DNS health check"
            }
        }
        else {
            $dnsHealth.Status = "Skipped"
            $dnsHealth.Message = "DNS health check skipped (DC not running or not accessible)"
            $dnsHealth.Checks += [PSCustomObject]@{
                Name = "DNS_Skipped"
                Status = "Skipped"
                Message = "DC not available for DNS checks"
            }
        }

        $result.DNSHealth = $dnsHealth
        $result.Checks += [PSCustomObject]@{
            Name = "DNS_Overall"
            Status = $dnsHealth.Status
            Message = $dnsHealth.Message
        }
        #endregion DNS Validation

        #region Domain Trust Verification
        # === Check 3: Member Server Health ===
        if ($IncludeMemberServers) {
            Write-Verbose "Checking member server health..."

            $memberVMs = @("svr1", "ws1")
            $dcHostForPing = "dc1"
            if (-not [string]::IsNullOrWhiteSpace($targetDomain)) {
                $dcHostForPing = "dc1.$targetDomain"
            }

            foreach ($memberVM in $memberVMs) {
                Write-Verbose "Checking member server '$memberVM'..."

                $memberHealth = [PSCustomObject]@{
                    VMName = $memberVM
                    Running = $false
                    Joined = $false
                    TrustEstablished = $false
                    CanPingDC = $false
                    Status = "Failed"
                    Message = ""
                    Checks = @()
                }

                # Check VM exists and is running
                $vm = Get-VM -Name $memberVM -ErrorAction SilentlyContinue
                if ($null -eq $vm) {
                    $memberHealth.Status = "NotFound"
                    $memberHealth.Message = "VM '$memberVM' does not exist"
                    $memberHealth.Checks += [PSCustomObject]@{
                        Name = "VM_Exists"
                        Status = "Skipped"
                        Message = "VM not found - may not be created yet"
                    }
                }
                elseif ($vm.State -ne "Running") {
                    $memberHealth.Status = "NotRunning"
                    $memberHealth.Message = "VM '$memberVM' is not running (State: $($vm.State))"
                    $memberHealth.Checks += [PSCustomObject]@{
                        Name = "VM_Running"
                        Status = "Fail"
                        Message = "VM not running - run Start-LabVMs first"
                    }
                }
                else {
                    $memberHealth.Running = $true
                    $memberHealth.Checks += [PSCustomObject]@{
                        Name = "VM_Running"
                        Status = "Pass"
                        Message = "VM is running"
                    }

                    # Check domain membership
                    try {
                        $joinTest = Test-LabDomainJoin -VMName $memberVM -DomainName $targetDomain -Credential $targetCredential -ErrorAction Stop

                        $memberHealth.Joined = $joinTest.IsJoined
                        $memberHealth.TrustEstablished = ($joinTest.TrustStatus -eq "OK")

                        if ($joinTest.IsJoined) {
                            $memberHealth.Checks += [PSCustomObject]@{
                                Name = "Domain_Joined"
                                Status = "Pass"
                                Message = "VM is joined to domain '$($joinTest.DomainName)'"
                            }
                        }
                        else {
                            $memberHealth.Checks += [PSCustomObject]@{
                                Name = "Domain_Joined"
                                Status = "Fail"
                                Message = "VM is not joined to domain - run Join-LabDomain first"
                            }
                        }

                        if ($joinTest.TrustStatus -eq "OK") {
                            $memberHealth.Checks += [PSCustomObject]@{
                                Name = "Domain_Trust"
                                Status = "Pass"
                                Message = "Domain trust is established"
                            }
                        }
                        elseif ($joinTest.IsJoined) {
                            $memberHealth.Checks += [PSCustomObject]@{
                                Name = "Domain_Trust"
                                Status = "Warning"
                                Message = "Joined but trust not established - may need time to settle"
                            }
                        }

                        # Check can ping DC
                        try {
                            $pingTest = Invoke-Command -VMName $memberVM -ScriptBlock {
                                param($dcHost)
                                Test-Connection -ComputerName $dcHost -Count 1 -Quiet -ErrorAction SilentlyContinue
                            } -ArgumentList $dcHostForPing -ErrorAction SilentlyContinue

                            if ($pingTest) {
                                $memberHealth.CanPingDC = $true
                                $memberHealth.Checks += [PSCustomObject]@{
                                    Name = "DC_Reachable"
                                    Status = "Pass"
                                    Message = "Can ping domain controller"
                                }
                            }
                            else {
                                $memberHealth.Checks += [PSCustomObject]@{
                                    Name = "DC_Reachable"
                                    Status = "Warning"
                                    Message = "Cannot ping domain controller (may still be starting up)"
                                }
                            }
                        }
                        catch {
                            $memberHealth.Checks += [PSCustomObject]@{
                                Name = "DC_Reachable"
                                Status = "Warning"
                                Message = "DC reachability check failed: $($_.Exception.Message)"
                            }
                        }

                        # Determine member health status
                        $memberFailures = ($memberHealth.Checks | Where-Object { $_.Status -eq "Fail" }).Count

                        if ($memberFailures -eq 0) {
                            $memberHealth.Status = "Healthy"
                            $memberHealth.Message = "Member server is healthy"
                        }
                        elseif ($memberHealth.Joined) {
                            $memberHealth.Status = "Warning"
                            $memberHealth.Message = "Member server joined with some warnings"
                        }
                        else {
                            $memberHealth.Status = "Failed"
                            $memberHealth.Message = "Member server check failed"
                        }
                    }
                    catch {
                        $memberHealth.Checks += [PSCustomObject]@{
                            Name = "Check_Error"
                            Status = "Error"
                            Message = "Member health check failed: $($_.Exception.Message)"
                        }
                        $memberHealth.Status = "Error"
                        $memberHealth.Message = "Could not complete member health check"
                    }
                }

                $result.MemberHealth += $memberHealth
                $result.Checks += [PSCustomObject]@{
                    Name = "Member_$memberVM"
                    Status = $memberHealth.Status
                    Message = $memberHealth.Message
                }
            }
        }
        #endregion Domain Trust Verification

        #region Result Compilation
        # === Overall Assessment ===
        Write-Verbose "Determining overall domain health status..."

        $allChecks = $result.Checks
        $failures = ($allChecks | Where-Object { $_.Status -eq "Fail" })
        $warnings = ($allChecks | Where-Object { $_.Status -eq "Warning" })
        $skipped = ($allChecks | Where-Object { $_.Status -eq "Skipped" })

        if ($dcHealth.Status -in @("Failed", "NotFound", "NotRunning")) {
            $result.OverallStatus = "NoDomain"
            $result.Message = "Domain does not exist or DC not running - run Initialize-LabDomain first"
        }
        elseif ($failures.Count -eq 0 -and $warnings.Count -eq 0) {
            $result.OverallStatus = "Healthy"
            $result.Message = "Domain is fully functional and all components are healthy"
        }
        elseif ($failures.Count -eq 0) {
            $result.OverallStatus = "Warning"
            $result.Message = "Domain is functional with $($warnings.Count) warning(s)"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Domain has $($failures.Count) failure(s) requiring attention"
        }

        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        Write-Verbose "Domain health validation completed: $($result.OverallStatus)"

        return $result
        #endregion Result Compilation
    }
    catch {
        $result.OverallStatus = "Error"
        $result.Message = "Domain health validation failed: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
