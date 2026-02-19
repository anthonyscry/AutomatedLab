Set-StrictMode -Version Latest

function Resolve-LabFailureCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Exception]$Exception
    )

    switch ($Exception) {
        { $_ -is [System.UnauthorizedAccessException] } { return 'PolicyBlocked' }
        { $_ -is [System.TimeoutException] } { return 'TimeoutExceeded' }
        { $_ -is [System.ArgumentException] } { return 'ConfigError' }
        default { return 'UnexpectedException' }
    }
}
