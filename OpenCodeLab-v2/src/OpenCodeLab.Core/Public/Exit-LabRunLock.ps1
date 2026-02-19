Set-StrictMode -Version Latest

function Exit-LabRunLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LockPath
    )

    if (Test-Path -Path $LockPath -PathType Leaf) {
        Remove-Item -Path $LockPath -Force -ErrorAction SilentlyContinue
    }
}
