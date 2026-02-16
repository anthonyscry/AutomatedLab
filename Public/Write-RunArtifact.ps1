function Write-RunArtifact {
    <#
    .SYNOPSIS
        Writes a run artifact JSON file to track operation results.

    .DESCRIPTION
        Creates a timestamped JSON artifact file in .planning/runs/ directory
        containing operation details, status, duration, exit code, host info,
        and optional error/custom data. Works cross-platform.

    .PARAMETER Operation
        The name of the operation being performed.

    .PARAMETER Status
        The status of the operation (e.g., "Success", "Failed", "Partial").

    .PARAMETER Duration
        Duration of the operation in seconds.

    .PARAMETER ExitCode
        Exit code for the operation.

    .PARAMETER VMNames
        Array of VM names affected by the operation.

    .PARAMETER Phase
        Project phase identifier (default: "01-project-foundation").

    .PARAMETER ErrorRecord
        Error record if the operation failed.

    .PARAMETER CustomData
        Hashtable of custom data to include in the artifact.

    .OUTPUTS
        String. Path to the created artifact file, or null on failure.

    .EXAMPLE
        Write-RunArtifact -Operation "CreateVM" -Status "Success" -Duration 45.2 -ExitCode 0 -VMNames @("dc1")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [double]$Duration,

        [Parameter(Mandatory)]
        [int]$ExitCode,

        [string[]]$VMNames = @(),

        [string]$Phase = "01-project-foundation",

        [Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $false)]
        [hashtable]$CustomData
    )

    try {
        # Generate timestamp for filename and ISO 8601 timestamp for content
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $isoTimestamp = (Get-Date).ToString("o")

        # Determine artifact path relative to repository root
        # Use Join-Path with proper separators for cross-platform compatibility
        # Note: Chain Join-Path for Windows PowerShell 5.1 compatibility
        $artifactDir = Join-Path $PSScriptRoot ".." | Join-Path -ChildPath ".planning" | Join-Path -ChildPath "runs"
        $artifactDir = Resolve-Path $artifactDir -ErrorAction SilentlyContinue

        if (-not $artifactDir) {
            # Create directory if it doesn't exist
            $tempPath = Join-Path $PSScriptRoot ".." | Join-Path -ChildPath ".planning" | Join-Path -ChildPath "runs"
            $artifactDir = New-Item -Path $tempPath -ItemType Directory -Force
            $artifactDir = $artifactDir.FullName
        }
        else {
            $artifactDir = $artifactDir.Path
        }

        $artifactPath = Join-Path $artifactDir "run-$timestamp.json"

        # Build artifact object using [ordered] hashtable for consistent property order
        $artifact = [ordered]@{
            Operation = $Operation
            Timestamp = $isoTimestamp
            Status = $Status
            Duration = $Duration
            ExitCode = $ExitCode
            VMNames = @($VMNames)  # Ensure array type
            Phase = $Phase
            HostInfo = Get-HostInfo
        }

        # Add error information if present (scrub credentials from error messages)
        if ($ErrorRecord) {
            $artifact.Error = [ordered]@{
                Message = Protect-LabLogString -InputString $ErrorRecord.Exception.Message
                Type = $ErrorRecord.Exception.GetType().FullName
                ScriptStackTrace = $ErrorRecord.ScriptStackTrace
            }
        }

        # Add custom data if present (scrub string values to prevent credential leakage)
        if ($CustomData) {
            foreach ($key in $CustomData.Keys) {
                $val = $CustomData[$key]
                if ($val -is [string]) {
                    $artifact[$key] = Protect-LabLogString -InputString $val
                } else {
                    $artifact[$key] = $val
                }
            }
        }

        # Convert to JSON with proper depth
        $json = $artifact | ConvertTo-Json -Depth 4

        # Write to file
        $json | Out-File -FilePath $artifactPath -Encoding utf8 -Force

        Write-Host "Run artifact saved to: $artifactPath"

        return $artifactPath
    }
    catch {
        Write-Error "Failed to write run artifact: $($_.Exception.Message)"
        return $null
    }
}
