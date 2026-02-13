# Get-LinuxVMIPv4.ps1 -- Resolve Linux VM IPv4 from Hyper-V adapter
function Get-LinuxVMIPv4 {
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
