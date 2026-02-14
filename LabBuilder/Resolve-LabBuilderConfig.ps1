function Resolve-LabBuilderConfig {
    <#
    .SYNOPSIS
        Loads LabBuilder configuration from the global config or legacy file.
    .DESCRIPTION
        Supports:
          - Lab-Config.ps1 (preferred one-stop config; expects $LabBuilderConfig)
          - Lab-Config.psd1 (expects top-level LabBuilder key)
          - Legacy LabBuilder/Config/LabDefaults.psd1 (flat LabBuilder config)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    $repoRoot = Split-Path $PSScriptRoot -Parent
    $defaultGlobalPs1 = Join-Path $repoRoot 'Lab-Config.ps1'
    $defaultLegacyPsd1 = Join-Path $PSScriptRoot 'Config\LabDefaults.psd1'

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (Test-Path $defaultGlobalPs1) {
            $ConfigPath = $defaultGlobalPs1
        } else {
            $ConfigPath = $defaultLegacyPsd1
        }
    }

    if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
        $relativeToLabBuilder = Join-Path $PSScriptRoot $ConfigPath
        if (Test-Path $relativeToLabBuilder) {
            $ConfigPath = $relativeToLabBuilder
        }
    }

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $extension = [System.IO.Path]::GetExtension($ConfigPath).ToLowerInvariant()

    if ($extension -eq '.ps1') {
        $config = & {
            param([string]$Path)

            . $Path

            if (Get-Variable -Name LabBuilderConfig -ErrorAction SilentlyContinue) {
                return (Get-Variable -Name LabBuilderConfig -ValueOnly)
            }

            if (Get-Variable -Name GlobalLabConfig -ErrorAction SilentlyContinue) {
                $global = Get-Variable -Name GlobalLabConfig -ValueOnly
                if ($global -and $global.Builder) {
                    return $global.Builder
                }
            }

            throw "Config script '$Path' did not define `$LabBuilderConfig."
        } -Path $ConfigPath

        return $config
    }

    if ($extension -eq '.psd1') {
        $rawConfig = Import-PowerShellDataFile -Path $ConfigPath

        if ($rawConfig -and $rawConfig.ContainsKey('LabBuilder')) {
            return $rawConfig.LabBuilder
        }

        return $rawConfig
    }

    throw "Unsupported config extension '$extension'. Use .ps1 or .psd1"
}
