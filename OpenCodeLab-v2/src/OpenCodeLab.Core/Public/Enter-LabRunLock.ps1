Set-StrictMode -Version Latest

function Enter-LabRunLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LockPath
    )

    $parentPath = Split-Path -Path $LockPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        $null = New-Item -Path $parentPath -ItemType Directory -Force
    }

    try {
        $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    }
    catch [System.IO.IOException] {
        throw 'PolicyBlocked: active run lock exists'
    }

    try {
        $hostName = [System.Environment]::MachineName
        $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
        $payload = "host=$hostName pid=$processId"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $lockStream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $lockStream.Dispose()
    }

    return $LockPath
}
