Set-StrictMode -Version Latest

function Exit-LabRunLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$LockHandle
    )

    $lockPath = [string]$LockHandle.Path
    $ownerToken = [string]$LockHandle.OwnerToken

    if ([string]::IsNullOrWhiteSpace($lockPath) -or [string]::IsNullOrWhiteSpace($ownerToken)) {
        throw 'InvalidArgument: LockHandle must include Path and OwnerToken'
    }

    try {
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    }
    catch [System.IO.FileNotFoundException] {
        return
    }
    catch [System.IO.DirectoryNotFoundException] {
        return
    }

    try {
        $reader = [System.IO.StreamReader]::new($lockStream, [System.Text.Encoding]::UTF8, $true, 1024, $true)
        try {
            $metadata = $reader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $lockStream.Dispose()
    }

    if ($null -eq $metadata -or [string]::IsNullOrWhiteSpace([string]$metadata.token)) {
        throw 'PolicyBlocked: run lock owner token mismatch'
    }

    if ([string]$metadata.token -ne $ownerToken) {
        throw 'PolicyBlocked: run lock owner token mismatch'
    }

    try {
        [System.IO.File]::Delete($lockPath)
    }
    catch [System.IO.FileNotFoundException] {
        return
    }
}
