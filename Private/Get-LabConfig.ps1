function Get-LabConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigPath = ".planning/config.json"
    )

    try {
        # Resolve path relative to module root ($PSScriptRoot is SimpleLab/ directory)
        $resolvedPath = Join-Path $PSScriptRoot "..\$ConfigPath"
        $resolvedPath = Resolve-Path $resolvedPath -ErrorAction SilentlyContinue

        if (-not $resolvedPath) {
            return $null
        }

        # Check if file exists
        if (-not (Test-Path -Path $resolvedPath -PathType Leaf)) {
            return $null
        }

        # Load and parse JSON
        $jsonContent = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
        $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop

        return $config
    }
    catch {
        Write-Error "Failed to load config from '$ConfigPath': $($_.Exception.Message)"
        return $null
    }
}
