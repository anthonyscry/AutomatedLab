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

    try {
        $normalizedAction = $Action.Trim().ToLowerInvariant()
        $hasProfilePath = -not [string]::IsNullOrWhiteSpace($ProfilePath)
        $teardownMayEscalate = ($normalizedAction -eq 'teardown') -and ($Mode -eq 'quick') -and $hasProfilePath
        $isOneButtonReset = $normalizedAction -eq 'one-button-reset'
        $requiresConfirmation = ($normalizedAction -eq 'blow-away') -or $isOneButtonReset -or (($normalizedAction -eq 'teardown') -and ($Mode -eq 'full')) -or $teardownMayEscalate

        $confirmationLabel = ''
        if ($normalizedAction -eq 'blow-away') {
            $confirmationLabel = 'BLOW AWAY'
        }
        elseif ($isOneButtonReset) {
            $confirmationLabel = 'ONE BUTTON RESET'
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
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Get-LabGuiDestructiveGuard: destructive guard check failed - $_", $_.Exception),
                'Get-LabGuiDestructiveGuard.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}
