Set-StrictMode -Version Latest

function Test-LabConfigSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Config
    )

    if (-not $Config.ContainsKey('Paths')) {
        throw 'Missing required section: Paths'
    }

    if (-not $Config.ContainsKey('Lab')) {
        throw 'Missing required section: Lab'
    }

    $paths = $Config['Paths']
    if ($paths -isnot [System.Collections.IDictionary]) {
        throw 'Invalid section type: Paths must be a hashtable'
    }

    if (-not $paths.Contains('LogRoot')) {
        throw 'Missing required key: Paths.LogRoot'
    }

    if ([string]::IsNullOrWhiteSpace([string]$paths['LogRoot'])) {
        throw 'Missing required key: Paths.LogRoot'
    }

    $lab = $Config['Lab']
    if ($lab -isnot [System.Collections.IDictionary]) {
        throw 'Invalid section type: Lab must be a hashtable'
    }

    if (-not $lab.Contains('Name')) {
        throw 'Missing required key: Lab.Name'
    }

    if ([string]::IsNullOrWhiteSpace([string]$lab['Name'])) {
        throw 'Missing required key: Lab.Name'
    }

    return $true
}
