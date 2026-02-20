# Add-LinuxDhcpReservation.ps1 -- Create DHCP reservation for Linux VM
function Add-LinuxDhcpReservation {
    <#
    .SYNOPSIS
        Creates a DHCP reservation on DC1 for a Linux VM's MAC address.

    .DESCRIPTION
        Reads the VM's MAC address from the Hyper-V network adapter and creates a
        DHCP reservation via Invoke-LabCommand on the DHCP server (DC1). This ensures
        the Linux VM always receives the same IP address after reboot.

        Any existing reservation for the same MAC address or IP address is removed
        before the new reservation is created, avoiding conflicts.

        NOTE: Requires AutomatedLab to be imported (Invoke-LabCommand prerequisite).

    .PARAMETER VMName
        Name of the Hyper-V virtual machine whose MAC address will be reserved.
        Defaults to 'LIN1'.

    .PARAMETER ReservedIP
        The IPv4 address to reserve for the VM. Defaults to the value of $LIN1_Ip
        if set, otherwise '10.0.10.110'.

    .PARAMETER DhcpServer
        The name of the DHCP server (lab computer) where the reservation will be
        created. Defaults to 'DC1'.

    .PARAMETER ScopeId
        The DHCP scope ID that contains the IP address. Defaults to the value of
        $DhcpScopeId if set, otherwise '10.0.10.0'.

    .EXAMPLE
        Add-LinuxDhcpReservation

        Creates a reservation for the default LIN1 VM using the default IP and scope.

    .EXAMPLE
        Add-LinuxDhcpReservation -VMName 'LIN2' -ReservedIP '10.0.10.120'

        Creates a DHCP reservation for LIN2 at address 10.0.10.120 on DC1.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [string]$ReservedIP = $(if ($LIN1_Ip) { $LIN1_Ip } else { '10.0.10.110' }),
        [string]$DhcpServer = 'DC1',
        [string]$ScopeId = $(if ($DhcpScopeId) { $DhcpScopeId } else { '10.0.10.0' })
    )

    $adapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $adapter -or [string]::IsNullOrWhiteSpace($adapter.MacAddress)) {
        Write-Warning "Cannot read MAC address for VM '$VMName'. Is it created?"
        return $false
    }

    $macRaw = ($adapter.MacAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($macRaw.Length -ne 12) {
        Write-Warning "Invalid MAC address for '$VMName': $($adapter.MacAddress)"
        return $false
    }

    # Format as AA-BB-CC-DD-EE-FF for DHCP server
    $macFormatted = ($macRaw -replace '(.{2})(?=.)', '$1-')

    try {
        Invoke-LabCommand -ComputerName $DhcpServer -ScriptBlock {
            param($ScopeArg, $IpArg, $MacArg, $NameArg)

            # Remove existing reservation for this MAC or IP if present
            Get-DhcpServerv4Reservation -ScopeId $ScopeArg -ErrorAction SilentlyContinue |
                Where-Object { $_.ClientId -eq $MacArg -or $_.IPAddress.IPAddressToString -eq $IpArg } |
                Remove-DhcpServerv4Reservation -ErrorAction SilentlyContinue

            Add-DhcpServerv4Reservation -ScopeId $ScopeArg `
                -IPAddress $IpArg `
                -ClientId $MacArg `
                -Name $NameArg `
                -Description "Linux VM $NameArg - auto-reserved" `
                -ErrorAction Stop

        } -ArgumentList $ScopeId, $ReservedIP, $macFormatted, $VMName

        Write-LabStatus -Status OK -Message "DHCP reservation: $VMName -> $ReservedIP (MAC: $macFormatted)" -Indent 2
        return $true
    }
    catch {
        Write-Warning "DHCP reservation failed for '$VMName': $($_.Exception.Message)"
        return $false
    }
}
