function ConvertTo-ModeDecisionBoolean {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Value
    )

    if ($Value -is [bool]) {
        return $Value
    }

    if ($Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]) {
        if ($Value -eq 1) { return $true }
        if ($Value -eq 0) { return $false }
        return $false
    }

    if ($Value -is [string]) {
        switch ($Value.Trim().ToLowerInvariant()) {
            'true' { return $true }
            'yes' { return $true }
            'on' { return $true }
            'false' { return $false }
            'no' { return $false }
            'off' { return $false }
            default { return $false }
        }
    }

    return $false
}

function Resolve-LabModeDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('deploy', 'teardown')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$RequestedMode,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$State
    )

    $effectiveMode = $RequestedMode
    $fallbackReason = $null

    if ($Operation -eq 'deploy' -and $RequestedMode -eq 'quick') {
        $propertyNames = @($State.PSObject.Properties.Name)
        $labRegistered = if ($propertyNames -contains 'LabRegistered') { ConvertTo-ModeDecisionBoolean -Value $State.LabRegistered } else { $false }
        $missingVMs = if ($propertyNames -contains 'MissingVMs') { @($State.MissingVMs) } else { @('unknown') }
        $labReadyAvailable = if ($propertyNames -contains 'LabReadyAvailable') { ConvertTo-ModeDecisionBoolean -Value $State.LabReadyAvailable } else { $false }
        $switchPresent = if ($propertyNames -contains 'SwitchPresent') { ConvertTo-ModeDecisionBoolean -Value $State.SwitchPresent } else { $false }
        $natPresent = if ($propertyNames -contains 'NatPresent') { ConvertTo-ModeDecisionBoolean -Value $State.NatPresent } else { $false }

        if (-not $labRegistered) {
            $effectiveMode = 'full'
            $fallbackReason = 'lab_not_registered'
        }
        elseif ((@($missingVMs)).Count -gt 0) {
            $effectiveMode = 'full'
            $fallbackReason = 'vm_state_inconsistent'
        }
        elseif (-not $labReadyAvailable) {
            $effectiveMode = 'full'
            $fallbackReason = 'missing_labready'
        }
        elseif ((-not $switchPresent) -or (-not $natPresent)) {
            $effectiveMode = 'full'
            $fallbackReason = 'infra_drift_detected'
        }
    }

    return [pscustomobject]@{
        RequestedMode = $RequestedMode
        EffectiveMode = $effectiveMode
        FallbackReason = $fallbackReason
    }
}
