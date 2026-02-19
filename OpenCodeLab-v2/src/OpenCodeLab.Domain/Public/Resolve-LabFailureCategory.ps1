Set-StrictMode -Version Latest

function Resolve-LabFailureCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    return 'UnexpectedException'
}
