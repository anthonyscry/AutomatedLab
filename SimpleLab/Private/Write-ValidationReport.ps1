function Write-ValidationReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Results,

        [Parameter(Mandatory = $false)]
        [switch]$Quiet
    )

    # Handle null results
    if ($null -eq $Results) {
        if (-not $Quiet) {
            Write-Host "`n=== SimpleLab Pre-flight Validation ===" -ForegroundColor Cyan
            Write-Host "Error: No validation results provided" -ForegroundColor Red
        }
        return [PSCustomObject]@{
            ExitCode = 2
            OverallStatus = "Error"
        }
    }

    # If quiet mode, just return exit code without writing to console
    if ($Quiet) {
        $exitCode = if ($Results.OverallStatus -eq "Pass") { 0 } else { 2 }
        return [PSCustomObject]@{
            ExitCode = $exitCode
            OverallStatus = $Results.OverallStatus
        }
    }

    # Display full validation report
    Write-Host "`n=== SimpleLab Pre-flight Validation ===" -ForegroundColor Cyan
    Write-Host "Checked at: $($Results.Timestamp)" -ForegroundColor Gray
    Write-Host "Duration: $([math]::Round($Results.Duration, 2)) seconds`n" -ForegroundColor Gray

    # Overall status
    $overallStatusColor = if ($Results.OverallStatus -eq "Pass") { "Green" } elseif ($Results.OverallStatus -eq "Fail") { "Red" } else { "Yellow" }
    Write-Host "Overall Status: $($Results.OverallStatus.ToUpper())" -ForegroundColor $overallStatusColor

    # Check results table
    Write-Host "`nCheck Results:" -ForegroundColor White
    foreach ($check in $Results.Checks) {
        $statusColor = if ($check.Status -eq "Pass") { "Green" } elseif ($check.Status -eq "Fail") { "Red" } elseif ($check.Status -eq "Warning") { "Yellow" } else { "Gray" }
        Write-Host "  [$($check.Status.ToUpper())] $($check.Name)" -ForegroundColor $statusColor

        if ($check.Message) {
            Write-Host "         $($check.Message)" -ForegroundColor Gray
        }

        # Special handling for ISO failures - show expected path and fix instructions
        if ($check.Name -like "ISO_*" -and $check.Status -eq "Fail") {
            if ($check.Message -match "Path:\s+(.+)") {
                $expectedPath = $matches[1]
                Write-Host "         Expected: $expectedPath" -ForegroundColor Yellow
            }
            Write-Host "         To fix: Edit .planning/config.json with correct ISO path" -ForegroundColor Yellow
        }
    }

    # Failed checks summary
    if ($Results.FailedChecks -and $Results.FailedChecks.Count -gt 0) {
        Write-Host "`nFailed Checks:" -ForegroundColor Red
        Write-Host "  $($Results.FailedChecks -join ', ')" -ForegroundColor Yellow
        Write-Host "`nPlease resolve the issues above before attempting lab build.`n" -ForegroundColor Yellow
    }
    else {
        Write-Host "`nAll prerequisites met. Ready to build lab.`n" -ForegroundColor Green
    }

    # Determine exit code
    $exitCode = if ($Results.OverallStatus -eq "Pass") { 0 } else { 2 }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        OverallStatus = $Results.OverallStatus
    }
}
