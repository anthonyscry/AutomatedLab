# Add-LinuxDhcpReservation.ps1 -- Create DHCP reservation for Linux VM
function Add-LinuxDhcpReservation {
    <#
    .SYNOPSIS
    Creates a DHCP reservation on DC1 for a Linux VM's MAC address.
    .DESCRIPTION
    Reads the VM's MAC from Hyper-V and creates a DHCP reservation via
    Invoke-LabCommand on the DHCP server (DC1). This ensures the Linux VM
    always gets the same IP after reboot.
    NOTE: Requires AutomatedLab to be imported (Invoke-LabCommand prerequisite).
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
