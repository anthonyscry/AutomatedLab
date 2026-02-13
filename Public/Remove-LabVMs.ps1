function Remove-LabVMs {
    <#
    .SYNOPSIS
        Removes all SimpleLab virtual machines.

    .DESCRIPTION
        Removes all lab VMs with confirmation prompts. Optionally removes VHD files.
        Preserves ISOs and virtual switch by default.

    .PARAMETER RemoveVHD
        Also delete VHD files associated with each VM.

    .PARAMETER Force
        Skip confirmation prompts and proceed with removal.

    .OUTPUTS
        PSCustomObject with removal results including VMsRemoved, FailedVMs,
        VHDsRemoved, OverallStatus, Message, and Duration.

    .EXAMPLE
        Remove-LabVMs

    .EXAMPLE
        Remove-LabVMs -RemoveVHD -Force
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$RemoveVHD,

        [Parameter()]
        [switch]$Force
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsRemoved = @()
        FailedVMs = @()
        VHDsRemoved = @()
        OverallStatus = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.OverallStatus = "Failed"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 2: Get VM configurations
        $vmConfigs = Get-LabVMConfig
        if ($null -eq $vmConfigs) {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to retrieve VM configurations"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 3: Find existing VMs
        $removalOrder = @("ws1", "svr1", "dc1")
        $existingVMs = @()

        foreach ($vmName in $removalOrder) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($vm) {
                $existingVMs += @{
                    Name = $vmName
                    State = $vm.State
                }
            }
        }

        if ($existingVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "No VMs to remove"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 4: Show VMs to be removed
        Write-Host ""
        Write-Host "The following VMs will be removed:" -ForegroundColor Yellow
        foreach ($vmInfo in $existingVMs) {
            Write-Host "  - $($vmInfo.Name) ($($vmInfo.State))" -ForegroundColor Cyan
        }

        if ($RemoveVHD) {
            Write-Host "VHD files will be DELETED" -ForegroundColor Red
        }
        else {
            Write-Host "VHD files will be preserved (use -RemoveVHD to delete)" -ForegroundColor Green
        }
        Write-Host ""

        # Step 5: Prompt for confirmation
        if (-not $Force) {
            $title = "Remove VMs"
            $message = "Do you want to remove these VMs?"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Remove the VMs"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Cancel removal"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $choice = $host.ui.PromptForChoice($title, $message, $options, 1)

            if ($choice -eq 1) {
                $result.OverallStatus = "Cancelled"
                $result.Message = "Removal cancelled by user"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }
        }

        # Step 6: Remove VMs in reverse dependency order
        foreach ($vmInfo in $existingVMs) {
            $vmName = $vmInfo.Name
            Write-Verbose "Removing VM '$vmName'..."

            try {
                # Build parameters for Remove-LabVM
                $removeParams = @{
                    VMName = $vmName
                    ErrorAction = "Stop"
                }

                if ($RemoveVHD) {
                    $removeParams.DeleteVHD = $true
                }

                # Remove the VM
                $removeResult = Remove-LabVM @removeParams

                if ($removeResult.OverallStatus -eq "OK") {
                    $result.VMsRemoved += $vmName
                    if ($RemoveVHD -and $removeResult.VHDDeleted) {
                        $result.VHDsRemoved += $removeResult.VHDDeleted
                    }
                    Write-Verbose "VM '$vmName' removed successfully"
                }
                else {
                    $result.FailedVMs += $vmName
                    Write-Warning "Failed to remove VM '$vmName': $($removeResult.Message)"
                }
            }
            catch {
                $result.FailedVMs += $vmName
                Write-Error "Error removing VM '$vmName': $($_.Exception.Message)"
            }
        }

        # Step 7: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $vhdMsg = if ($RemoveVHD) { " and $($result.VHDsRemoved.Count) VHD(s)" } else { "" }
            $result.Message = "Removed $($result.VMsRemoved.Count) VM(s)$vhdMsg"
        }
        elseif ($result.VMsRemoved.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Removed $($result.VMsRemoved.Count) VM(s), failed $($result.FailedVMs.Count)"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to remove any VMs"
        }

        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
