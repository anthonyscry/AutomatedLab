function Reset-Lab {
    <#
    .SYNOPSIS
        Completely resets the SimpleLab environment.

    .DESCRIPTION
        Removes all VMs, checkpoints, and the virtual switch for a complete lab reset.
        This is the "clean slate" command that tears down everything.

    .PARAMETER RemoveVHD
        Also delete VHD files associated with each VM.

    .PARAMETER Force
        Skip confirmation prompts and proceed with reset.

    .OUTPUTS
        PSCustomObject with reset results including VMsRemoved, CheckpointsRemoved,
        VSwitchRemoved, VHDsRemoved, OverallStatus, Message, and Duration.

    .EXAMPLE
        Reset-Lab

    .EXAMPLE
        Reset-Lab -RemoveVHD -Force
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
        CheckpointsRemoved = 0
        VSwitchRemoved = $false
        VHDsRemoved = @()
        FailedVMs = @()
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

        # Step 2: Check what exists
        $labVMs = if (Test-Path variable:GlobalLabConfig) { @($GlobalLabConfig.Lab.CoreVMNames) } else { @("dc1", "svr1", "ws1") }
        $existingVMs = @()
        $totalCheckpoints = 0

        foreach ($vmName in $labVMs) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($vm) {
                $existingVMs += @{
                    Name = $vmName
                    State = $vm.State
                }
                $checkpoints = @(Get-VMCheckpoint -VMName $vmName -ErrorAction SilentlyContinue)
                $totalCheckpoints += $checkpoints.Count
            }
        }

        $switchName = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Network.SwitchName } else { 'SimpleLab' }
        $vSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue

        # Step 3: Show what will be removed
        Write-Host ""
        $labDisplayName = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Lab.Name } else { 'SimpleLab' }
        Write-Host "$labDisplayName Clean Slate Reset" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Gray
        Write-Host ""
        Write-Host "This will completely reset the lab:" -ForegroundColor Yellow
        Write-Host ""

        if ($existingVMs.Count -gt 0) {
            Write-Host "VMs to remove:" -ForegroundColor White
            foreach ($vmInfo in $existingVMs) {
                $vmCheckpoints = @(Get-VMCheckpoint -VMName $vmInfo.Name -ErrorAction SilentlyContinue).Count
                $checkpointNote = if ($vmCheckpoints -gt 0) { " ($vmCheckpoints checkpoint(s))" } else { "" }
                Write-Host "  - $($vmInfo.Name) ($($vmInfo.State))$checkpointNote" -ForegroundColor Cyan
            }
            Write-Host ""
        }

        if ($totalCheckpoints -gt 0) {
            Write-Host "Total checkpoints: $totalCheckpoints" -ForegroundColor White
            Write-Host ""
        }

        if ($vSwitch) {
            Write-Host "Virtual switch: $switchName (Type: $($vSwitch.SwitchType))" -ForegroundColor White
            Write-Host ""
        }

        if ($RemoveVHD) {
            Write-Host "VHD files will be DELETED" -ForegroundColor Red
        }
        else {
            Write-Host "VHD files will be preserved (use -RemoveVHD to delete)" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "This is a DESTRUCTIVE operation." -ForegroundColor Red
        Write-Host ""

        # Step 4: Prompt for confirmation
        if (-not $Force) {
            $title = "Clean Slate Reset"
            $message = "Do you want to completely reset the lab?"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Reset the lab"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Cancel reset"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $choice = $host.ui.PromptForChoice($title, $message, $options, 1)

            if ($choice -eq 1) {
                $result.OverallStatus = "Cancelled"
                $result.Message = "Lab reset cancelled by user"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }
        }

        # Step 4.5: Unregister TTL monitoring task
        Write-Host ""
        Write-Host "Removing TTL monitoring task..." -ForegroundColor Cyan
        try {
            $ttlResult = Unregister-LabTTLTask
            if ($ttlResult.TaskRemoved) {
                Write-Host "  Removed TTL monitoring task" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "TTL task cleanup failed: $($_.Exception.Message)"
        }

        # Step 5: Remove checkpoints first
        Write-Host ""
        Write-Host "Removing checkpoints..." -ForegroundColor Cyan
        $checkpointResult = Remove-LabCheckpoint
        $result.CheckpointsRemoved = $checkpointResult.CheckpointsRemoved
        if ($checkpointResult.CheckpointsRemoved -gt 0) {
            Write-Host "  Removed $($checkpointResult.CheckpointsRemoved) checkpoint(s)" -ForegroundColor Green
        }

        # Step 6: Remove VMs
        Write-Host "Removing VMs..." -ForegroundColor Cyan
        $removeParams = @{
            Force = $true
            ErrorAction = "Stop"
        }

        if ($RemoveVHD) {
            $removeParams.RemoveVHD = $true
        }

        $vmRemoveResult = Remove-LabVMs @removeParams

        $result.VMsRemoved = $vmRemoveResult.VMsRemoved
        $result.FailedVMs = $vmRemoveResult.FailedVMs
        if ($RemoveVHD) {
            $result.VHDsRemoved = $vmRemoveResult.VHDsRemoved
        }

        if ($result.VMsRemoved.Count -gt 0) {
            Write-Host "  Removed $($result.VMsRemoved.Count) VM(s)" -ForegroundColor Green
        }

        # Step 7: Remove virtual switch
        Write-Host "Removing virtual switch..." -ForegroundColor Cyan
        $switchResult = Remove-LabSwitch -Force
        $result.VSwitchRemoved = ($switchResult.OverallStatus -eq "OK" -and $switchResult.Message -notlike "*does not exist*")

        if ($result.VSwitchRemoved) {
            Write-Host "  Removed virtual switch '$switchName'" -ForegroundColor Green
        }
        elseif ($switchResult.Message -like "*does not exist*") {
            Write-Host "  Virtual switch '$switchName' does not exist" -ForegroundColor Gray
        }

        # Step 8: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($result.FailedVMs.Count -eq 0) {
            $result.OverallStatus = "OK"
            $parts = @()
            if ($result.VMsRemoved.Count -gt 0) { $parts += "$($result.VMsRemoved.Count) VM(s)" }
            if ($result.CheckpointsRemoved -gt 0) { $parts += "$($result.CheckpointsRemoved) checkpoint(s)" }
            if ($result.VSwitchRemoved) { $parts += "virtual switch" }
            if ($RemoveVHD -and $result.VHDsRemoved.Count -gt 0) { $parts += "$($result.VHDsRemoved.Count) VHD(s)" }

            $partsList = $parts -join ", "
            $result.Message = if ($partsList) { "Lab reset complete: removed $partsList" } else { "Lab already clean" }
        }
        elseif ($result.VMsRemoved.Count -gt 0) {
            $result.OverallStatus = "Partial"
            $result.Message = "Lab partially reset: removed $($result.VMsRemoved.Count) VM(s), failed $($result.FailedVMs.Count)"
        }
        else {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to reset lab"
        }

        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Gray
        Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Yellow" })
        Write-Host ""

        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
