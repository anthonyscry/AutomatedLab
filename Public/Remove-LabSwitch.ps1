function Remove-LabSwitch {
    <#
    .SYNOPSIS
        Removes the SimpleLab virtual switch.

    .DESCRIPTION
        Removes the SimpleLab virtual switch if it exists.
        Useful for complete lab cleanup.

    .PARAMETER Force
        Skip confirmation prompts.

    .OUTPUTS
        PSCustomObject with switch removal results.

    .EXAMPLE
        Remove-LabSwitch
        Prompts for confirmation before removing the SimpleLab virtual switch.

    .EXAMPLE
        Remove-LabSwitch -Force
        Removes the SimpleLab switch without prompting. Safe to use in scripts.

    .EXAMPLE
        (Remove-LabSwitch -Force).OverallStatus
        Removes the switch and verifies the result is "OK" or "Cancelled".
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Force
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        SwitchName = "SimpleLab"
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

        # Step 2: Check if switch exists
        $vSwitch = Get-VMSwitch -Name "SimpleLab" -ErrorAction SilentlyContinue

        if ($null -eq $vSwitch) {
            $result.OverallStatus = "OK"
            $result.Message = "Virtual switch 'SimpleLab' does not exist"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 3: Show what will be removed
        Write-Host ""
        Write-Host "Virtual switch to remove:" -ForegroundColor Yellow
        Write-Host "  - SimpleLab (Type: $($vSwitch.SwitchType))" -ForegroundColor Cyan
        Write-Host ""

        # Step 4: Prompt for confirmation
        if (-not $Force) {
            $title = "Remove Virtual Switch"
            $message = "Do you want to remove the SimpleLab virtual switch?"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Remove the switch"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Cancel removal"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $choice = $host.ui.PromptForChoice($title, $message, $options, 1)

            if ($choice -eq 1) {
                $result.OverallStatus = "Cancelled"
                $result.Message = "Switch removal cancelled by user"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }
        }

        # Step 5: Remove the switch
        Write-Verbose "Removing virtual switch 'SimpleLab'..."

        try {
            Remove-VMSwitch -Name "SimpleLab" -Force -ErrorAction Stop
            $result.OverallStatus = "OK"
            $result.Message = "Virtual switch 'SimpleLab' removed successfully"
        }
        catch {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to remove switch: $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}
