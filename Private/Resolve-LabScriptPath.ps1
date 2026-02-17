function Resolve-LabScriptPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseName,
        [Parameter(Mandatory)][string]$ScriptDir
    )

    # Search root first, then Scripts/ subfolder
    $path = Join-Path $ScriptDir "$BaseName.ps1"
    if (Test-Path $path) { return $path }
    $altPath = Join-Path $ScriptDir "Scripts\$BaseName.ps1"
    if (Test-Path $altPath) { return $altPath }
    throw "Script not found: $path (also checked Scripts\$BaseName.ps1)"
}
