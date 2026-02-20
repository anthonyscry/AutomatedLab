# Get-LinuxVMIPv4.ps1 -- Resolve Linux VM IPv4 from Hyper-V adapter
function Get-LinuxVMIPv4 {
    <#
    .SYNOPSIS
        Resolves the IPv4 address of a Linux VM from its Hyper-V network adapter.

    .DESCRIPTION
        Queries the Hyper-V network adapter for the specified VM and returns the first
        non-link-local IPv4 address found. Link-local addresses (169.254.x.x) are
        excluded. Returns $null if the VM has no adapter or no valid IP address.

    .PARAMETER VMName
        Name of the Hyper-V virtual machine to query. Defaults to 'LIN1'.

    .EXAMPLE
        Get-LinuxVMIPv4

        Returns the current IPv4 address of the default LIN1 VM, or $null if unavailable.

    .EXAMPLE
        $ip = Get-LinuxVMIPv4 -VMName 'LIN2'
        if ($ip) { Write-Host "LIN2 is at $ip" }

        Retrieves the IP for LIN2 and displays it if resolved.
    #>
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1'
    )

    $adapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $adapter) { return $null }

    $ipList = @()
    if ($adapter.PSObject.Properties.Name -contains 'IPAddresses') {
        $ipList = @($adapter.IPAddresses)
    }

    $ip = $ipList |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } |
        Select-Object -First 1
    return $ip
}
