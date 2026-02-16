function Write-ValidationReport {
    <#
    .SYNOPSIS
        Renders a formatted pre-flight validation report to the console.

    .DESCRIPTION
        Takes the results object from Test-LabPrereqs and displays a
        color-coded summary of all checks. Shows pass/fail status for
        each check, ISO path fix instructions for failures, and returns
        an exit code (0 = pass, 2 = fail/error).

    .PARAMETER Results
        Validation results object from Test-LabPrereqs containing Checks,
        OverallStatus, FailedChecks, Timestamp, and Duration.

    .PARAMETER Quiet
        Suppress console output and return only the exit code object.

    .OUTPUTS
        PSCustomObject with ExitCode and OverallStatus properties.

    .EXAMPLE
        $results = Test-LabPrereqs
        Write-ValidationReport -Results $results

    .EXAMPLE
        $report = Write-ValidationReport -Results $results -Quiet
        exit $report.ExitCode
    #>
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
        # Only for main ISO entries, not search results (which end with _Search)
        if ($check.Name -like "ISO_*" -and $check.Status -eq "Fail" -and $check.Name -notlike "*_Search") {
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
