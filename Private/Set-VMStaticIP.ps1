function Set-VMStaticIP {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
        [string]$IPAddress,

        [Parameter()]
        [ValidateRange(1,32)]
        [int]$PrefixLength = 24,

        [Parameter()]
        [string]$InterfaceAlias = "Ethernet"
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        IPAddress = $IPAddress
        Configured = $false
        Status = "Failed"
        Message = ""
    }

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Message = "Hyper-V module is not available"
            $result.Status = "Failed"
            return $result
        }

        # Check if VM exists
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.Message = "VM '$VMName' not found"
            $result.Status = "VMNotFound"
            return $result
        }

        # Check if VM is running
        if ($vm.State -ne 'Running') {
            $result.Message = "VM '$VMName' is not running (State: $($vm.State))"
            $result.Status = "Failed"
            return $result
        }

        # Use PowerShell Direct to configure IP inside the VM
        $scriptBlock = {
            param($ip, $prefix, $interface)

            try {
                # Get the network adapter
                $adapter = Get-NetAdapter -Name $interface -ErrorAction Stop

                # Remove any existing IP addresses
                Remove-NetIPAddress -InterfaceAlias $interface -Confirm:$false -ErrorAction SilentlyContinue

                # Configure the new static IP
                New-NetIPAddress -IPAddress $ip -PrefixLength $prefix -InterfaceAlias $interface -ErrorAction Stop

                # Remove any existing default gateway (for isolated network)
                Remove-NetRoute -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue

                # Clear DNS servers (will be configured by DC in Phase 5)
                Set-DnsClientServerAddress -InterfaceAlias $interface -ResetServerAddresses -ErrorAction SilentlyContinue

                return @{
                    Success = $true
                    Message = "IP configured successfully"
                }
            }
            catch {
                return @{
                    Success = $false
                    Message = "Failed to configure IP: $($_.Exception.Message)"
                }
            }
        }

        # Execute inside VM using PowerShell Direct
        $vmResult = Invoke-Command -VMName $VMName -ScriptBlock $scriptBlock -ArgumentList $IPAddress, $PrefixLength, $InterfaceAlias -ErrorAction Stop

        if ($vmResult.Success) {
            $result.Configured = $true
            $result.Status = "OK"
            $result.Message = "VM '$VMName' configured with IP $IPAddress/$PrefixLength"
        }
        else {
            $result.Status = "Failed"
            $result.Message = "Failed to configure '$VMName': $($vmResult.Message)"
        }
    }
    catch {
        $result.Status = "Failed"
        $result.Message = "Failed to configure '$VMName': $($_.Exception.Message)"
    }

    return $result
}
