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
        # Resolve target path (absolute path honored, otherwise relative to repo root)
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $targetPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
            $ConfigPath
        } else {
            Join-Path $repoRoot $ConfigPath
        }
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($targetPath)

        # Check if config already exists
        if (Test-Path -Path $resolvedPath -PathType Leaf) {
            if (-not $Force) {
                # Load and return existing config
                $jsonContent = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
                $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                return $config
            }
        }

        # Ensure destination directory exists
        $targetDir = Split-Path -Parent $resolvedPath
        if (-not (Test-Path -Path $targetDir -PathType Container)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
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
