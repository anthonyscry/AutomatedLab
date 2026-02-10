function Save-LabReadyCheckpoint {
    <#
    .SYNOPSIS
        Creates a LabReady checkpoint for all lab VMs.

    .DESCRIPTION
        Creates a baseline checkpoint of the lab after validating domain health.
        The checkpoint name includes a timestamp for uniqueness. Use this after
        completing domain configuration to create a known-good restore point.

    .PARAMETER Force
        Skip domain health validation before creating checkpoint.

    .OUTPUTS
        PSCustomObject with checkpoint creation results.

    .EXAMPLE
        Save-LabReadyCheckpoint

    .EXAMPLE
        Save-LabReadyCheckpoint -Force
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Force
    )

    # Start timing
    $startTime = Get-Date

    # Generate checkpoint name with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $checkpointName = "LabReady-$timestamp"

    # Initialize result object
    $result = [PSCustomObject]@{
        CheckpointName = $checkpointName
        VMsCheckpointed = @()
        DomainHealthStatus = "Unknown"
        OverallStatus = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        # Step 1: Validate domain health (unless -Force)
        if (-not $Force) {
            Write-Host "Validating domain health before creating LabReady checkpoint..." -ForegroundColor Cyan

            $healthResult = Test-LabDomainHealth -ErrorAction SilentlyContinue

            if ($null -eq $healthResult) {
                $result.OverallStatus = "Failed"
                $result.Message = "Failed to validate domain health"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            $result.DomainHealthStatus = $healthResult.OverallStatus

            if ($healthResult.OverallStatus -ne "Healthy") {
                $result.OverallStatus = "Failed"
                $result.Message = "Domain is not healthy (status: $($healthResult.OverallStatus)). Use -Force to create checkpoint anyway."
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            Write-Host "  Domain health: $($healthResult.OverallStatus)" -ForegroundColor Green
        }
        else {
            Write-Host "Skipping domain health validation (-Force specified)" -ForegroundColor Yellow
        }

        # Step 2: Create checkpoint for all VMs
        Write-Host "Creating LabReady checkpoint: $checkpointName" -ForegroundColor Cyan

        try {
            $checkpointResult = Save-LabCheckpoint -CheckpointName $checkpointName -ErrorAction Stop

            $result.VMsCheckpointed = $checkpointResult.VMsCheckpointed
            $result.OverallStatus = $checkpointResult.OverallStatus

            if ($checkpointResult.OverallStatus -eq "OK") {
                $result.Message = "LabReady checkpoint '$checkpointName' created for $($result.VMsCheckpointed.Count) VM(s)"
                Write-Host "  Checkpoint created for $($result.VMsCheckpointed.Count) VM(s)" -ForegroundColor Green
            }
            else {
                $result.Message = $checkpointResult.Message
            }
        }
        catch {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to create checkpoint: $($_.Exception.Message)"
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
