# Resolve-LabNoExecuteStateOverride.ps1
# Resolves the state override for NoExecute mode from JSON string or file path.
# Returns the parsed state (or array of host probes), or $null if not in NoExecute mode.

function Resolve-LabNoExecuteStateOverride {
    [CmdletBinding()]
    param(
        [switch]$NoExecute,
        [string]$NoExecuteStateJson,
        [string]$NoExecuteStatePath
    )

    if (-not $NoExecute) {
        return $null
    }

    $state = $null

    if (-not [string]::IsNullOrWhiteSpace($NoExecuteStateJson)) {
        $state = ($NoExecuteStateJson | ConvertFrom-Json)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($NoExecuteStatePath)) {
        if (-not (Test-Path $NoExecuteStatePath)) {
            throw "NoExecute state path not found: $NoExecuteStatePath"
        }

        $state = (Get-Content -Raw -Path $NoExecuteStatePath | ConvertFrom-Json)
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
