function Remove-LabVM {
    <#
    .SYNOPSIS
        Removes a SimpleLab virtual machine.

    .DESCRIPTION
        Removes the specified VM from Hyper-V. Optionally deletes the
        associated VHD file. The VM is stopped before removal if running.

    .PARAMETER VMName
        Name of the VM to remove.

    .PARAMETER DeleteVHD
        If specified, also deletes the VHD file associated with the VM.

    .OUTPUTS
        PSCustomObject with VMName, Removed (bool), Status, Message, and VHDDeleted (bool).

    .EXAMPLE
        Remove-LabVM -VMName "dc1"

    .EXAMPLE
        Remove-LabVM -VMName "dc1" -DeleteVHD
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$VMName,

        [Parameter()]
        [switch]$DeleteVHD
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        Removed = $false
        Status = "Failed"
        Message = ""
        VHDDeleted = $false
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status = "Failed"
            $result.Message = "Hyper-V module is not available"
            return $result
        }

        # Step 2: Check if VM exists
        $vmTest = Test-LabVM -VMName $VMName
        $vmExists = $vmTest.Exists

        if (-not $vmExists) {
            $result.Status = "NotFound"
            $result.Removed = $false
            $result.Message = "VM '$VMName' not found"
            return $result
        }

        # Step 3: Stop VM if running
        try {
            $vm = Get-VM -Name $VMName -ErrorAction Stop
            if ($vm.State -ne 'Off') {
                Stop-VM -Name $VMName -TurnOff -Force -ErrorAction Stop
                Start-Sleep -Seconds 1
            }
        }
        catch {
            $result.Status = "Failed"
            $result.Message = "Failed to stop VM: $($_.Exception.Message)"
            return $result
        }

        # Step 4: Store VHD path for potential deletion
        $vhdPath = $null
        if ($DeleteVHD) {
            try {
                $vhd = Get-VMHardDiskDrive -VMName $VMName -ErrorAction Stop
                if ($vhd) {
                    $vhdPath = $vhd.Path
                }
            }
            catch {
                # Continue even if we can't get VHD path
            }
        }

        # Step 5: Remove the VM
        try {
            Remove-VM -Name $VMName -Force -ErrorAction Stop
            $result.Removed = $true
        }
        catch {
            $result.Status = "Failed"
            $result.Message = "Failed to remove VM: $($_.Exception.Message)"
            return $result
        }

        # Step 6: Delete VHD if requested
        if ($DeleteVHD -and $vhdPath) {
            if (Test-Path -Path $vhdPath -PathType Leaf) {
                try {
                    Remove-Item -Path $vhdPath -Force -ErrorAction Stop
                    $result.VHDDeleted = $true
                }
                catch {
                    $result.VHDDeleted = $false
                }
            }
            else {
                $result.VHDDeleted = $false
            }
        }

        $result.Status = "OK"
        $result.Message = "VM '$VMName' removed successfully"
    }
    catch {
        $result.Status = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
    }

    return $result
}
