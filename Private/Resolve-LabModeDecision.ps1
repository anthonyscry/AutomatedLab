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
        $labRegistered = if ($propertyNames -contains 'LabRegistered') { [bool]$State.LabRegistered } else { $false }
        $missingVMs = if ($propertyNames -contains 'MissingVMs') { @($State.MissingVMs) } else { @('unknown') }
        $labReadyAvailable = if ($propertyNames -contains 'LabReadyAvailable') { [bool]$State.LabReadyAvailable } else { $false }
        $switchPresent = if ($propertyNames -contains 'SwitchPresent') { [bool]$State.SwitchPresent } else { $false }
        $natPresent = if ($propertyNames -contains 'NatPresent') { [bool]$State.NatPresent } else { $false }

        if (-not $labRegistered) {
            $effectiveMode = 'full'
            $fallbackReason = 'lab_not_registered'
        }
        elseif ($missingVMs.Count -gt 0) {
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
