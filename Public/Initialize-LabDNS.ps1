function Initialize-LabDNS {
    <#
    .SYNOPSIS
        Configures DNS forwarders on the domain controller.

    .DESCRIPTION
        Configures DNS forwarders for Internet resolution and validates DNS
        functionality. Uses PowerShell Direct for in-VM configuration.

    .PARAMETER VMName
        Name of the domain controller VM (default: "dc1").

    .PARAMETER Forwarder
        IP addresses of DNS forwarders (default: Google DNS: 8.8.8.8, 8.8.4.4).

    .PARAMETER Force
        Reconfigure forwarders even if they already exist.

    .OUTPUTS
        PSCustomObject with configuration status and details.

    .EXAMPLE
        Initialize-LabDNS

    .EXAMPLE
        Initialize-LabDNS -Forwarder @("1.1.1.1", "8.8.8.8") -Force
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$VMName = "dc1",

        [Parameter()]
        [ipaddress[]]$Forwarder = @([ipaddress]"8.8.8.8", [ipaddress]"8.8.4.4"),

        [Parameter()]
        [switch]$Force
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        Configured = $false
        Status = "Failed"
        Message = ""
        ForwardersConfigured = @()
        Duration = $null
    }

    try {
        Write-Verbose "Starting DNS configuration for '$VMName'..."

        # Step 1: Verify VM is running
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.Status = "NotFound"
            $result.Message = "VM '$VMName' does not exist"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        if ($vm.State -ne "Running") {
            $result.Status = "NotRunning"
            $result.Message = "VM '$VMName' is not running (State: $($vm.State))"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        Write-Verbose "VM is running, checking DNS configuration..."

        # Step 2: Check current forwarder configuration via PowerShell Direct
        try {
            $currentForwarders = Invoke-Command -VMName $VMName -ScriptBlock {
                Get-DnsServerForwarder -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty IPAddress
            } -ErrorAction SilentlyContinue

            $forwarderList = if ($currentForwarders) { $currentForwarders } else { @() }

            if ($forwarderList.Count -gt 0 -and -not $Force) {
                $result.Status = "AlreadyConfigured"
                $result.Configured = $false
                $result.ForwardersConfigured = [string[]]$forwarderList
                $result.Message = "DNS forwarders already configured: $($forwarderList -join ', ')"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                Write-Verbose "Forwarders already configured, use -Force to reconfigure"
                return $result
            }

            # If Force specified, remove existing forwarders first
            if ($Force -and $forwarderList.Count -gt 0) {
                Write-Verbose "Removing existing forwarders..."
                Write-Verbose "Removing existing DNS forwarders on '$VMName'..."
                $null = Invoke-Command -VMName $VMName -ScriptBlock {
                    Remove-DnsServerForwarder -All -Force -ErrorAction Stop
                } -ErrorAction Stop
            }

            Write-Verbose "Configuring forwarders: $($Forwarder -join ', ')"

            # Step 3: Add new forwarders
            Write-Verbose "Configuring DNS forwarders on '$VMName'..."
            $null = Invoke-Command -VMName $VMName -ScriptBlock {
                param($forwarders)

                # Add each forwarder
                foreach ($ip in $forwarders) {
                    Write-Verbose "Adding forwarder: $ip"
                    Add-DnsServerForwarder -IPAddress $ip -ErrorAction Stop
                }

                return $forwarders
            } -ArgumentList $Forwarder -ErrorAction Stop

            $result.ForwardersConfigured = [string[]]$Forwarder

            Write-Verbose "Forwarders configured successfully"

            # Step 4: Validate DNS is responding
            Write-Verbose "Validating DNS functionality..."
            $dnsValidation = Invoke-Command -VMName $VMName -ScriptBlock {
                # Wait a moment for DNS to stabilize
                Start-Sleep -Seconds 2

                # Test DNS response
                $dnsTest = Test-DnsServerDnsServer -ComputerName localhost -ErrorAction SilentlyContinue

                return @{
                    Responding = if ($null -ne $dnsTest) { $true } else { $false }
                }
            } -ErrorAction SilentlyContinue

            if ($dnsValidation -and $dnsValidation.Responding) {
                Write-Verbose "DNS server is responding"
            }
            else {
                Write-Warning "DNS server validation failed, but forwarders were configured"
            }

            # Step 5: Test Internet resolution if forwarders were configured
            $internetTest = $false
            try {
                $internetResult = Invoke-Command -VMName $VMName -ScriptBlock {
                    # Wait for DNS to be ready
                    Start-Sleep -Seconds 2

                    # Test resolution
                    $resolve = Resolve-DnsName -Name "google.com" -QuickTimeout -ErrorAction SilentlyContinue
                    return $null -ne $resolve
                } -ErrorAction SilentlyContinue

                $internetTest = if ($internetResult) { $true } else { $false }

                if ($internetTest) {
                    Write-Verbose "Internet resolution is working"
                }
                else {
                    Write-Verbose "Internet resolution test failed (forwarders may take time to propagate)"
                }
            }
            catch {
                Write-Verbose "Internet resolution test skipped: $($_.Exception.Message)"
            }

            # Success!
            $result.Configured = $true
            $result.Status = "OK"
            $internetNote = if ($internetTest) { "; Internet resolution working" } else { "" }
            $result.Message = "Configured DNS forwarders: $($Forwarder -join ', ')$internetNote"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            Write-Verbose "DNS configuration completed successfully"

            return $result
        }
        catch {
            # Check for "not a DC" error
            if ($_.Exception.Message -match "not a domain controller|ADDSDomainController") {
                $result.Status = "NotADC"
                $result.Message = "VM '$VMName' is not a domain controller. Run Initialize-LabDomain first."
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            throw
        }
    }
    catch {
        $result.Status = "Failed"
        $result.Message = "DNS configuration failed: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
