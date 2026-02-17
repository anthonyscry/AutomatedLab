if (-not ('LabCoordinatorPolicyOutcome' -as [type])) {
    Add-Type -TypeDefinition @"
public enum LabCoordinatorPolicyOutcome
{
    PolicyBlocked = 0,
    EscalationRequired = 1,
    Approved = 2
}
"@
}

function ConvertTo-CoordinatorPolicyBoolean {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Value
    )

    if ($Value -is [bool]) {
        return $Value
    }

    if ($Value -is [string]) {
        switch ($Value.Trim().ToLowerInvariant()) {
            'true' { return $true }
            'yes' { return $true }
            '1' { return $true }
            default { return $false }
        }
    }

    if ($Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]) {
        return ($Value -eq 1)
    }

    return $false
}

function Resolve-LabCoordinatorPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('deploy', 'teardown')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$RequestedMode,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$HostProbes,

        [Parameter()]
        [bool]$SafetyRequiresFull = $false,

        [Parameter()]
        [bool]$HasScopedConfirmation = $false
    )

    try {
        $effectiveMode = $RequestedMode
        $unreachableHost = $null
        $probeCount = @($HostProbes).Count

        if ($probeCount -eq 0) {
            return [pscustomobject]@{
                Allowed = $false
                Outcome = [LabCoordinatorPolicyOutcome]::PolicyBlocked
                Reason = 'host_probes_missing'
                EffectiveMode = $effectiveMode
                RequestedMode = $RequestedMode
                HasScopedConfirmation = $HasScopedConfirmation
            }
        }

        foreach ($probe in @($HostProbes)) {
            $propertyNames = @($probe.PSObject.Properties.Name)
            $isReachable = if ($propertyNames -contains 'Reachable') {
                ConvertTo-CoordinatorPolicyBoolean -Value $probe.Reachable
            }
            else {
                $false
            }

            if (-not $isReachable) {
                if ($propertyNames -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$probe.Name)) {
                    $unreachableHost = [string]$probe.Name
                }
                else {
                    $unreachableHost = 'unknown'
                }

                break
            }
        }

        if ($unreachableHost) {
            return [pscustomobject]@{
                Allowed = $false
                Outcome = [LabCoordinatorPolicyOutcome]::PolicyBlocked
                Reason = 'host_probe_unreachable:{0}' -f $unreachableHost
                EffectiveMode = $effectiveMode
                RequestedMode = $RequestedMode
                HasScopedConfirmation = $HasScopedConfirmation
            }
        }

        if ($Action -eq 'teardown' -and $RequestedMode -eq 'quick' -and $SafetyRequiresFull) {
            return [pscustomobject]@{
                Allowed = $false
                Outcome = [LabCoordinatorPolicyOutcome]::EscalationRequired
                Reason = 'quick_teardown_requires_full'
                EffectiveMode = 'full'
                RequestedMode = $RequestedMode
                HasScopedConfirmation = $HasScopedConfirmation
            }
        }

        if ($Action -eq 'teardown' -and $effectiveMode -eq 'full' -and -not $HasScopedConfirmation) {
            return [pscustomobject]@{
                Allowed = $false
                Outcome = [LabCoordinatorPolicyOutcome]::PolicyBlocked
                Reason = 'missing_scoped_confirmation'
                EffectiveMode = 'full'
                RequestedMode = $RequestedMode
                HasScopedConfirmation = $HasScopedConfirmation
            }
        }

        return [pscustomobject]@{
            Allowed = $true
            Outcome = [LabCoordinatorPolicyOutcome]::Approved
            Reason = 'approved'
            EffectiveMode = $effectiveMode
            RequestedMode = $RequestedMode
            HasScopedConfirmation = $HasScopedConfirmation
        }
    }
    catch {
        throw "Resolve-LabCoordinatorPolicy: failed to evaluate coordinator policy - $_"
    }
}
