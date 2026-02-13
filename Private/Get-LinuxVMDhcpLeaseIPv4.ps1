# Get-LinuxVMDhcpLeaseIPv4.ps1 -- Resolve Linux VM IP from DHCP lease
function Get-LinuxVMDhcpLeaseIPv4 {
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [string]$DhcpServer = 'DC1',
        [string]$ScopeId = '10.0.10.0'
    )

    $adapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $adapter -or [string]::IsNullOrWhiteSpace($adapter.MacAddress)) {
        return $null
    }

    $macCompact = ($adapter.MacAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($macCompact.Length -ne 12) { return $null }
    $macHyphen = ($macCompact -replace '(.{2})(?=.)','$1-').TrimEnd('-')

    try {
        $leaseResult = Invoke-LabCommand -ComputerName $DhcpServer -PassThru -ErrorAction SilentlyContinue -ScriptBlock {
            param($LeaseScope, $MacCompactArg, $MacHyphenArg, $VmNameArg)

            $leases = Get-DhcpServerv4Lease -ScopeId $LeaseScope -ErrorAction SilentlyContinue
            if (-not $leases) { return $null }

            $match = $leases | Where-Object {
                $cid = (($_.ClientId | Out-String).Trim() -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
                $cid -eq $MacCompactArg
            } | Select-Object -First 1

            if (-not $match) {
                $match = $leases | Where-Object {
                    (($_.ClientId | Out-String).Trim().ToUpperInvariant() -eq $MacHyphenArg) -or
                    ($_.HostName -eq $VmNameArg)
                } | Select-Object -First 1
            }

            if ($match -and $match.IPAddress) {
                return $match.IPAddress.IPAddressToString
            }

            return $null
        } -ArgumentList $ScopeId, $macCompact, $macHyphen, $VMName

        if ($leaseResult) {
            return ($leaseResult | Select-Object -First 1)
        }
    } catch {
        return $null
    }

    return $null
}
