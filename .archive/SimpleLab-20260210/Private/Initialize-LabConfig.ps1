function Initialize-LabConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigPath = ".planning/config.json",

        [Parameter()]
        [switch]$Force
    )

    try {
        # Resolve path relative to module root ($PSScriptRoot is SimpleLab/ directory)
        $resolvedPath = Join-Path $PSScriptRoot "..\$ConfigPath"
        $resolvedPath = Resolve-Path $resolvedPath -ErrorAction SilentlyContinue

        # Check if config already exists
        if ($resolvedPath -and (Test-Path -Path $resolvedPath -PathType Leaf)) {
            if (-not $Force) {
                # Load and return existing config
                $jsonContent = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
                $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                return $config
            }
        }

        # Ensure .planning directory exists
        $planningDir = Join-Path $PSScriptRoot "..\.planning"
        if (-not (Test-Path -Path $planningDir -PathType Container)) {
            New-Item -Path $planningDir -ItemType Directory -Force | Out-Null
        }

        # Determine final config file path
        if (-not $resolvedPath) {
            $resolvedPath = Join-Path $PSScriptRoot "..\$ConfigPath"
            $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($resolvedPath)
        }

        # Create default config object
        $defaultConfig = [PSCustomObject]@{
            IsoPaths = [PSCustomObject]@{
                Server2019 = "C:\Lab\ISOs\Server2019.iso"
                Windows11 = "C:\Lab\ISOs\Windows11.iso"
            }
            IsoSearchPaths = @(
                "C:\Lab\ISOs",
                "D:\ISOs",
                ".\ISOs"
            )
            Requirements = [PSCustomObject]@{
                MinDiskSpaceGB = 100
                MinMemoryGB = 16
            }
        }

        # Convert to JSON with depth 4 and write to file
        $json = $defaultConfig | ConvertTo-Json -Depth 4
        $json | Out-File -FilePath $resolvedPath -Encoding utf8 -Force

        return $defaultConfig
    }
    catch {
        Write-Error "Failed to initialize config at '$ConfigPath': $($_.Exception.Message)"
        return $null
    }
}
