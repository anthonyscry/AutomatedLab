Set-StrictMode -Version Latest

function Resolve-LabTeardownPolicy {
    [CmdletBinding()]
    param(
        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full',

        [switch]$Force
    )

    if ($Mode -eq 'full' -and -not $Force.IsPresent) {
        return [pscustomobject]@{
            Outcome   = 'PolicyBlocked'
            ErrorCode = 'CONFIRMATION_REQUIRED'
        }
    }

    return [pscustomobject]@{
        Outcome   = 'Approved'
        ErrorCode = $null
    }
}
