function New-LabVMNetworkAdapter {
    <#
    .SYNOPSIS
        Connects a VM's network adapter to a specific named Hyper-V switch with optional VLAN tagging.

    .DESCRIPTION
        Idempotent helper that connects a VM's first network adapter to a named virtual switch and
        optionally configures a VLAN ID (Access mode) on that adapter.

        Idempotency: If the adapter is already connected to the correct switch with the correct VLAN
        configuration, it returns OK without making any changes.

        If -Force is specified and the adapter is on a different switch, it will be reconnected.
        Without -Force, an adapter already on a different switch results in a Failed result.

    .PARAMETER VMName
        Name of the virtual machine to configure.

    .PARAMETER SwitchName
        Name of the Hyper-V virtual switch to connect the adapter to.

    .PARAMETER VlanId
        Optional VLAN ID to apply in Access mode. When 0 or not specified, no VLAN is set.

    .PARAMETER Force
        If specified, reconnects the adapter even if it is already on a different switch.

    .OUTPUTS
        PSCustomObject with VMName, SwitchName, VlanId, Status, and Message.

    .EXAMPLE
        New-LabVMNetworkAdapter -VMName 'SVR1' -SwitchName 'LabCorpNet' -VlanId 100
        Connects SVR1's adapter to LabCorpNet and sets VLAN 100.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter()]
        [int]$VlanId = 0,

        [Parameter()]
        [switch]$Force
    )

    Set-StrictMode -Version Latest

    $result = [PSCustomObject]@{
        VMName     = $VMName
        SwitchName = $SwitchName
        VlanId     = if ($VlanId -gt 0) { $VlanId } else { $null }
        Status     = 'Failed'
        Message    = ''
    }

    try {
        # 1. Check if VM exists
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.Message = "New-LabVMNetworkAdapter: VM '$VMName' not found"
            return $result
        }

        # 2. Get existing adapter (first adapter)
        $adapter = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($null -ne $adapter) {
            $currentSwitch = $adapter.SwitchName

            if ($currentSwitch -eq $SwitchName) {
                # Already on the correct switch -- check VLAN idempotency
                $vlanInfo = Get-VMNetworkAdapterVlan -VMName $VMName -ErrorAction SilentlyContinue | Select-Object -First 1
                $currentVlan = if ($null -ne $vlanInfo) { $vlanInfo.AccessVlanId } else { 0 }

                if ($VlanId -gt 0) {
                    if ($currentVlan -ne $VlanId) {
                        # Need to set/update VLAN
                        Set-VMNetworkAdapterVlan -VMName $VMName -Access -VlanId $VlanId -ErrorAction Stop
                    }
                    # else: VLAN already correct, nothing to do
                }
                # else: no VLAN required -- idempotent OK regardless of current VLAN

                $result.Status  = 'OK'
                $result.Message = "New-LabVMNetworkAdapter: '$VMName' already connected to '$SwitchName' (idempotent)"
                return $result
            }

            # Adapter exists but on a different switch (or no switch yet)
            $isUnconnected = [string]::IsNullOrWhiteSpace($currentSwitch)
            if (-not $isUnconnected -and -not $Force) {
                # Adapter is on a real different switch and -Force not specified
                $result.Message = "New-LabVMNetworkAdapter: '$VMName' adapter is on switch '$currentSwitch', not '$SwitchName'. Use -Force to reconnect."
                return $result
            }

            # Connect (or reconnect with -Force) adapter to the named switch
            Connect-VMNetworkAdapter -VMNetworkAdapter $adapter -SwitchName $SwitchName -ErrorAction Stop
        }
        else {
            # No existing adapter found -- connect to named switch
            Connect-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName -ErrorAction Stop
        }

        # 5. Set VLAN if VlanId > 0
        if ($VlanId -gt 0) {
            Set-VMNetworkAdapterVlan -VMName $VMName -Access -VlanId $VlanId -ErrorAction Stop
        }

        $result.Status  = 'OK'
        $result.Message = "New-LabVMNetworkAdapter: '$VMName' connected to '$SwitchName'" + $(if ($VlanId -gt 0) { " with VLAN $VlanId" } else { '' })
        return $result
    }
    catch {
        $result.Status  = 'Failed'
        $result.Message = "New-LabVMNetworkAdapter: error configuring '$VMName' - $_"
        return $result
    }
}
