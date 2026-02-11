function Test-LabCleanup {
    <#
    .SYNOPSIS
        Validates lab cleanup status after teardown operations.

    .DESCRIPTION
        Checks for orphaned VMs, checkpoints, and virtual switch artifacts.
        Returns pass/fail status for complete cleanup validation.

    .PARAMETER ExpectVMs
        Expect VMs to exist (for pre-teardown validation).

    .PARAMETER ExpectSwitch
        Expect virtual switch to exist.

    .OUTPUTS
        PSCustomObject with cleanup validation results.

    .EXAMPLE
        Test-LabCleanup

    .EXAMPLE
        Test-LabCleanup -ExpectVMs
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$ExpectVMs,

        [Parameter()]
        [switch]$ExpectSwitch
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsFound = @()
        CheckpointsFound = 0
        SwitchExists = $false
        OverallStatus = "Clean"
        Message = ""
        Checks = @()
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

        $labVMs = @("dc1", "svr1", "ws1")
        $allPassed = $true

        # Step 2: Check for orphaned VMs
        Write-Verbose "Checking for orphaned VMs..."
        $orphanedVMs = @()

        foreach ($vmName in $labVMs) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($vm) {
                $orphanedVMs += $vmName

                # Check for checkpoints
                $checkpoints = Get-VMCheckpoint -VMName $vmName -ErrorAction SilentlyContinue
                if ($checkpoints) {
                    $result.CheckpointsFound += $checkpoints.Count
                }
            }
        }

        $result.VMsFound = $orphanedVMs

        $vmCheckStatus = if ($ExpectVMs) {
            if ($orphanedVMs.Count -gt 0) { "Pass" } else { "Warning" }
        }
        else {
            if ($orphanedVMs.Count -eq 0) { "Pass" } else { "Fail" }
        }

        if ($vmCheckStatus -ne "Pass") {
            $allPassed = $false
        }

        $result.Checks += [PSCustomObject]@{
            Name = "VMs"
            Status = $vmCheckStatus
            Found = $orphanedVMs
            Expected = if ($ExpectVMs) { "Yes" } else { "No" }
            Message = if ($ExpectVMs) {
                if ($orphanedVMs.Count -eq 0) { "No VMs found (expected VMs to exist)" }
                else { "Found $($orphanedVMs.Count) VM(s)" }
            }
            else {
                if ($orphanedVMs.Count -eq 0) { "No orphaned VMs" }
                else { "Found $($orphanedVMs.Count) orphaned VM(s)" }
            }
        }

        # Step 3: Check for orphaned checkpoints
        Write-Verbose "Checking for orphaned checkpoints..."
        $checkpointStatus = if ($result.CheckpointsFound -eq 0) { "Pass" } else { "Fail" }

        if ($checkpointStatus -eq "Fail") {
            $allPassed = $false
        }

        $result.Checks += [PSCustomObject]@{
            Name = "Checkpoints"
            Status = $checkpointStatus
            Found = $result.CheckpointsFound
            Expected = 0
            Message = if ($result.CheckpointsFound -eq 0) { "No orphaned checkpoints" }
                       else { "Found $($result.CheckpointsFound) orphaned checkpoint(s)" }
        }

        # Step 4: Check virtual switch
        Write-Verbose "Checking virtual switch..."
        $vSwitch = Get-VMSwitch -Name "SimpleLab" -ErrorAction SilentlyContinue
        $result.SwitchExists = ($null -ne $vSwitch)

        $switchStatus = if ($ExpectSwitch) {
            if ($result.SwitchExists) { "Pass" } else { "Warning" }
        }
        else {
            if (-not $result.SwitchExists) { "Pass" } else { "Fail" }
        }

        if ($switchStatus -ne "Pass") {
            $allPassed = $false
        }

        $result.Checks += [PSCustomObject]@{
            Name = "VirtualSwitch"
            Status = $switchStatus
            Found = $result.SwitchExists
            Expected = if ($ExpectSwitch) { "Yes" } else { "No" }
            Message = if ($ExpectSwitch) {
                if ($result.SwitchExists) { "Virtual switch exists" }
                else { "Virtual switch not found (expected)" }
            }
            else {
                if ($result.SwitchExists) { "Virtual switch still exists" }
                else { "No virtual switch found" }
            }
        }

        # Step 5: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($allPassed) {
            $result.OverallStatus = "Clean"
            $result.Message = "Lab is clean - no orphaned artifacts found"
        }
        elseif ($result.VMsFound.Count -gt 0 -or $result.CheckpointsFound -gt 0 -or $result.SwitchExists) {
            $result.OverallStatus = "NeedsCleanup"
            $issues = @()
            if ($result.VMsFound.Count -gt 0) { $issues += "$($result.VMsFound.Count) VM(s)" }
            if ($result.CheckpointsFound -gt 0) { $issues += "$($result.CheckpointsFound) checkpoint(s)" }
            if ($result.SwitchExists) { $issues += "virtual switch" }
            $result.Message = "Cleanup needed: found $($issues -join ', ')"
        }
        else {
            $result.OverallStatus = "Warning"
            $result.Message = "Some validation warnings detected"
        }

        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Validation error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
