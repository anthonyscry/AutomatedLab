Set-StrictMode -Version Latest

function New-LabActionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$RequestedMode
    )

    return [pscustomobject]@{
        RunId           = [guid]::NewGuid().ToString()
        Action          = $Action
        RequestedMode   = $RequestedMode
        EffectiveMode   = $RequestedMode
        PolicyOutcome   = 'Approved'
        Succeeded       = $false
        FailureCategory = $null
        ErrorCode       = $null
        RecoveryHint    = $null
        ArtifactPath    = $null
        DurationMs      = 0
    }
}
