# SimpleLab.ps1
# Main entry point for SimpleLab operations

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Test-HyperV', 'Test-Artifact', 'Validate')]
    [string]$Operation = 'Test-HyperV'
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$exitCode = 0
$vmNames = @()

try {
    Write-Host "SimpleLab v0.1.0 - Starting operation: $Operation" -ForegroundColor Cyan

    # Import module
    $modulePath = Join-Path $PSScriptRoot 'SimpleLab.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    # Check Hyper-V first for non-Validate operations (per user decision: check on every operation)
    if ($Operation -ne 'Validate') {
        Write-Host "Checking Hyper-V availability..."
        if (-not (Test-HyperVEnabled)) {
            $exitCode = 2  # Validation failure
            throw "Hyper-V validation failed"
        }
    }

    # Perform operation
    switch ($Operation) {
        'Test-HyperV' {
            Write-Host "Hyper-V is available and enabled" -ForegroundColor Green
            $status = "Success"
        }
        'Test-Artifact' {
            Write-Host "Testing run artifact generation..."
            $status = "Success"
        }
        'Validate' {
            Write-Host "Running pre-flight validation..." -ForegroundColor Cyan
            $validationResults = Test-LabPrereqs
            $reportResult = Write-ValidationReport -Results $validationResults

            # Set exit code based on validation result
            $exitCode = $reportResult.ExitCode
            $status = if ($exitCode -eq 0) { "Success" } else { "Failed" }

            # Include validation results in run artifact
            $vmNames = @()  # No VMs in validation
        }
        default {
            throw "Unknown operation: $Operation"
        }
    }
}
catch {
    # Surface the error
    Write-Error "Operation failed: $($_.Exception.Message)"

    # Set appropriate exit code based on error type
    if ($_.Exception.Message -match "network") { $exitCode = 3 }
    elseif ($_.Exception.Message -match "VM") { $exitCode = 4 }
    elseif ($_.Exception.Message -match "domain") { $exitCode = 5 }
    else { $exitCode = 1 }

    $status = "Failed"
}
finally {
    # Always generate run artifact (per user decision)
    $duration = (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
    $errorRecord = if ($exitCode -ne 0) { $_ } else { $null }

    # For Validate operation, include validation results in artifact
    if ($Operation -eq 'Validate' -and $null -ne $validationResults) {
        Write-RunArtifact -Operation $Operation -Status $status -Duration $duration -ExitCode $exitCode -VMNames $vmNames -ErrorRecord $errorRecord -CustomData @{
            ValidationResults = $validationResults
        }
    }
    else {
        Write-RunArtifact -Operation $Operation -Status $status -Duration $duration -ExitCode $exitCode -VMNames $vmNames -ErrorRecord $errorRecord
    }
}

exit $exitCode
