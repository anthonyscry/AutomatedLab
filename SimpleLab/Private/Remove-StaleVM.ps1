function Remove-StaleVM {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$LabVMs = @("SimpleDC", "SimpleServer", "SimpleWin11"),

        [Parameter()]
        [switch]$Force
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsRemoved = @()
        SkippedVMs = @()
        OverallStatus = "Failed"
        Message = ""
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.OverallStatus = "Failed"
            $result.Message = "Hyper-V module is not available"
            return $result
        }

        # Step 2: Get all VMs to check against
        $allVMs = Get-VM -ErrorAction SilentlyContinue
        if ($null -eq $allVMs) {
            $result.OverallStatus = "OK"
            $result.Message = "No VMs found on system"
            return $result
        }

        # Step 3: Process each LabVM
        $removedCount = 0
        $skippedCount = 0

        foreach ($vmName in $LabVMs) {
            $vm = $allVMs | Where-Object { $_.Name -eq $vmName }

            if ($null -eq $vm) {
                # VM doesn't exist - skip
                $result.SkippedVMs += $vmName
                $skippedCount++
                continue
            }

            # Determine if VM is stale (needs removal)
            $isStale = $false
            $staleReason = ""

            if ($Force) {
                # Force parameter removes all LabVMs unconditionally
                $isStale = $true
                $staleReason = "Force parameter specified"
            }
            else {
                # Check stale conditions
                $vmState = $vm.State

                # Condition 1: VM in incomplete states (Saved, Paused, Critical)
                if ($vmState -in @("Saved", "Paused", "Critical")) {
                    $isStale = $true
                    $staleReason = "VM state is '$vmState' (incomplete state)"
                }

                # Condition 2: VM exists but has no VHD attached
                try {
                    $vhd = Get-VMHardDiskDrive -VMName $vmName -ErrorAction SilentlyContinue
                    if ($null -eq $vhd) {
                        $isStale = $true
                        $staleReason = "VM has no VHD attached"
                    }
                    else {
                        # Condition 3: VHD file is missing
                        $vhdPath = $vhd.Path
                        if (-not (Test-Path -Path $vhdPath -PathType Leaf -ErrorAction SilentlyContinue)) {
                            $isStale = $true
                            $staleReason = "VHD file is missing: $vhdPath"
                        }
                    }
                }
                catch {
                    # If we can't check VHD, consider it stale
                    $isStale = $true
                    $staleReason = "Failed to check VHD: $($_.Exception.Message)"
                }
            }

            # Step 4: Remove stale VM
            if ($isStale) {
                try {
                    # Stop VM if not Off
                    if ($vm.State -ne "Off") {
                        Stop-VM -Name $vmName -TurnOff -Force -ErrorAction Stop | Out-Null
                        Start-Sleep -Seconds 1
                    }

                    # Remove VM
                    Remove-VM -Name $vmName -Force -ErrorAction Stop | Out-Null
                    $result.VMsRemoved += $vmName
                    $removedCount++

                    # Remove checkpoint files if any
                    $checkpointPath = "C:\Lab\VMs\$vmName"
                    if (Test-Path -Path $checkpointPath -ErrorAction SilentlyContinue) {
                        Remove-Item -Path "$checkpointPath\*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                catch {
                    # Continue on individual VM failures
                    Write-Verbose "Failed to remove VM '$vmName': $($_.Exception.Message)"
                    $result.SkippedVMs += $vmName
                    $skippedCount++
                }
            }
            else {
                # VM is not stale - skip
                $result.SkippedVMs += $vmName
                $skippedCount++
            }
        }

        # Step 5: Determine overall status
        if ($removedCount -gt 0 -and $skippedCount -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Removed $removedCount stale VM(s)"
        }
        elseif ($removedCount -gt 0 -and $skippedCount -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Removed $removedCount stale VM(s), skipped $skippedCount VM(s)"
        }
        elseif ($removedCount -eq 0 -and $skippedCount -gt 0) {
            $result.OverallStatus = "OK"
            $result.Message = "No stale VMs found (skipped $skippedCount VM(s))"
        }
        else {
            $result.OverallStatus = "OK"
            $result.Message = "No stale VMs found"
        }
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
    }

    return $result
}
