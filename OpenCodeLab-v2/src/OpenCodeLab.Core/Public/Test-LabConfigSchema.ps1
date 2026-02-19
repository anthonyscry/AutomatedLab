Set-StrictMode -Version Latest

function Test-LabConfigSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Config
    )

    if (-not $Config.ContainsKey('Paths')) {
        throw 'Missing required key: Paths.LogRoot'
    }

    $paths = $Config['Paths']
    if ($paths -isnot [System.Collections.IDictionary]) {
        throw 'Missing required key: Paths.LogRoot'
    }

    if (-not $paths.Contains('LogRoot')) {
        throw 'Missing required key: Paths.LogRoot'
    }

    if ([string]::IsNullOrWhiteSpace([string]$paths['LogRoot'])) {
        throw 'Missing required key: Paths.LogRoot'
    }

    return $true
}
