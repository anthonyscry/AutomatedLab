Set-StrictMode -Version Latest

function Get-LabConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Config file not found: $Path"
    }

    $config = Import-PowerShellDataFile -Path $Path
    if ($config -isnot [hashtable]) {
        throw 'Config root must be a hashtable'
    }

    Test-LabConfigSchema -Config $config | Out-Null
    return $config
}
