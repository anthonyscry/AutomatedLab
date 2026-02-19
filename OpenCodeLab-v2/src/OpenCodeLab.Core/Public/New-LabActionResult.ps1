Set-StrictMode -Version Latest

function New-LabActionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RequestedMode
    )

    return [pscustomobject][ordered]@{
        RunId           = ([guid]::NewGuid()).ToString()
        Action          = $Action
        RequestedMode   = $RequestedMode
        EffectiveMode   = $RequestedMode
        PolicyOutcome   = 'Approved'
        Succeeded       = $false
        FailureCategory = $null
        ErrorCode       = $null
        RecoveryHint    = $null
        ArtifactPath    = $null
        DurationMs      = [int]0
    }
}
