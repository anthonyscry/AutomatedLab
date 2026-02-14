function Get-LabGuiDestructiveGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$Mode
    )

    $normalizedAction = $Action.Trim().ToLowerInvariant()
    $requiresConfirmation = ($normalizedAction -eq 'blow-away') -or (($normalizedAction -eq 'teardown') -and ($Mode -eq 'full'))

    $confirmationLabel = ''
    if ($normalizedAction -eq 'blow-away') {
        $confirmationLabel = 'BLOW AWAY'
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
