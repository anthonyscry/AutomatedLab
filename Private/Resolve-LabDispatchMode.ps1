function Resolve-LabDispatchMode {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Mode,

        [Parameter()]
        [hashtable]$Config
    )

    $supportedModes = @('off', 'canary', 'enforced')
    $resolvedMode = 'off'
    $source = 'default'

    if ($PSBoundParameters.ContainsKey('Mode')) {
        if ([string]::IsNullOrWhiteSpace($Mode)) {
            throw 'Mode cannot be empty when explicitly provided.'
        }

        $resolvedMode = $Mode.Trim().ToLowerInvariant()
        $source = 'parameter'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_DISPATCH_MODE)) {
        $resolvedMode = $env:OPENCODELAB_DISPATCH_MODE.Trim().ToLowerInvariant()
        $source = 'environment'
    }
    elseif ($null -ne $Config -and $Config.ContainsKey('DispatchMode') -and -not [string]::IsNullOrWhiteSpace([string]$Config['DispatchMode'])) {
        $resolvedMode = ([string]$Config['DispatchMode']).Trim().ToLowerInvariant()
        $source = 'config'
    }

    if ($supportedModes -notcontains $resolvedMode) {
        throw "Unsupported dispatch mode '$resolvedMode'. Supported values: off, canary, enforced."
    }

    return [pscustomobject]@{
        Mode = $resolvedMode
        Source = $source
        ExecutionEnabled = ($resolvedMode -ne 'off')
    }
}
