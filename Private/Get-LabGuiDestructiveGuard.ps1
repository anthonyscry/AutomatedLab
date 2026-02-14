function Get-LabGuiDestructiveGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$Mode,

        [string]$ProfilePath
    )

    $normalizedAction = $Action.Trim().ToLowerInvariant()
    $hasProfilePath = -not [string]::IsNullOrWhiteSpace($ProfilePath)
    $teardownMayEscalate = ($normalizedAction -eq 'teardown') -and ($Mode -eq 'quick') -and $hasProfilePath
    $requiresConfirmation = ($normalizedAction -eq 'blow-away') -or (($normalizedAction -eq 'teardown') -and ($Mode -eq 'full')) -or $teardownMayEscalate

    $confirmationLabel = ''
    if ($normalizedAction -eq 'blow-away') {
        $confirmationLabel = 'BLOW AWAY'
    }
    elseif ($teardownMayEscalate) {
        $confirmationLabel = 'POTENTIAL FULL TEARDOWN'
    }
    elseif (($normalizedAction -eq 'teardown') -and ($Mode -eq 'full')) {
        $confirmationLabel = 'FULL TEARDOWN'
    }

    return [pscustomobject]@{
        RequiresConfirmation = $requiresConfirmation
        RecommendedNonInteractiveDefault = (-not $requiresConfirmation)
        ConfirmationLabel = $confirmationLabel
    }
}
