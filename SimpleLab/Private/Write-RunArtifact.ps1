function Write-RunArtifact {
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
        # $PSScriptRoot is SimpleLab/ directory, so we go up one level
        $artifactDir = Join-Path $PSScriptRoot "..\.planning\runs"
        $artifactDir = Resolve-Path $artifactDir -ErrorAction SilentlyContinue

        if (-not $artifactDir) {
            # Create directory if it doesn't exist
            $artifactDir = New-Item -Path (Join-Path $PSScriptRoot "..\.planning\runs") -ItemType Directory -Force
            $artifactDir = $artifactDir.FullName
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

        # Add error information if present
        if ($ErrorRecord) {
            $artifact.Error = [ordered]@{
                Message = $ErrorRecord.Exception.Message
                Type = $ErrorRecord.Exception.GetType().FullName
                ScriptStackTrace = $ErrorRecord.ScriptStackTrace
            }
        }

        # Add custom data if present (e.g., validation results)
        if ($CustomData) {
            foreach ($key in $CustomData.Keys) {
                $artifact[$key] = $CustomData[$key]
            }
        }

        # Convert to JSON with proper depth (avoid truncation per Pitfall 3)
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
