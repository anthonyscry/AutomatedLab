# Resolve-LabRuntimeStateOverride.ps1
# Resolves the state override from the OPENCODELAB_RUNTIME_STATE_JSON environment variable.
# Used in test/CI mode when SkipRuntimeBootstrap is active.
# Returns the parsed state, or $null if not in skip-bootstrap mode or env var is empty.

function Resolve-LabRuntimeStateOverride {
    [CmdletBinding()]
    param(
        [switch]$SkipRuntimeBootstrap
    )

    if (-not $SkipRuntimeBootstrap) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($env:OPENCODELAB_RUNTIME_STATE_JSON)) {
        return $null
    }

    $state = $null
    try {
        $state = ($env:OPENCODELAB_RUNTIME_STATE_JSON | ConvertFrom-Json)
    }
    catch {
        throw "Runtime state override JSON is invalid."
    }

    if ($null -eq $state) {
        return $null
    }

    if ($state -is [System.Array]) {
        return @($state)
    }

    if ($state -is [System.Collections.IEnumerable] -and $state -isnot [string] -and $state.PSObject.TypeNames -contains 'System.Object[]') {
        return @($state)
    }

    $statePropertyNames = @($state.PSObject.Properties.Name)
    if (($statePropertyNames -contains 'Reachable') -or ($statePropertyNames -contains 'HostName')) {
        return @($state)
    }

    if ($statePropertyNames -contains 'HostProbes') {
        return @($state.HostProbes)
    }

    if ($statePropertyNames -contains 'MissingVMs') {
        $state.MissingVMs = @($state.MissingVMs)
    }
    else {
        $state | Add-Member -NotePropertyName 'MissingVMs' -NotePropertyValue @()
    }

    return $state
}
