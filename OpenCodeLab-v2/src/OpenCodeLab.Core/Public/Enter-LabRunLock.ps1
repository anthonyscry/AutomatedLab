Set-StrictMode -Version Latest

function Enter-LabRunLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LockPath
    )

    function Get-LabRunLockMetadata {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        try {
            $raw = [System.IO.File]::ReadAllText($Path)
            return ($raw | ConvertFrom-Json)
        }
        catch {
            return $null
        }
    }

    function Test-LabProcessAlive {
        param(
            [Parameter(Mandatory)]
            [int]$ProcessId
        )

        try {
            $null = [System.Diagnostics.Process]::GetProcessById($ProcessId)
            return $true
        }
        catch [System.ArgumentException] {
            return $false
        }
        catch {
            return $true
        }
    }

    function Remove-LabRunLockIfTokenMatches {
        param(
            [Parameter(Mandatory)]
            [string]$Path,
            [Parameter(Mandatory)]
            [string]$OwnerToken
        )

        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        }
        catch [System.IO.FileNotFoundException] {
            return $false
        }
        catch [System.IO.DirectoryNotFoundException] {
            return $false
        }
        catch [System.IO.IOException] {
            return $false
        }

        try {
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true, 1024, $true)
            try {
                $metadata = $reader.ReadToEnd() | ConvertFrom-Json
            }
            finally {
                $reader.Dispose()
            }

            if ($null -eq $metadata -or [string]::IsNullOrWhiteSpace([string]$metadata.token)) {
                return $false
            }

            if ([string]$metadata.token -ne $OwnerToken) {
                return $false
            }
        }
        catch {
            return $false
        }
        finally {
            $stream.Dispose()
        }

        try {
            [System.IO.File]::Delete($Path)
            return $true
        }
        catch {
            return $false
        }
    }

    $parentPath = Split-Path -Path $LockPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        $null = New-Item -Path $parentPath -ItemType Directory -Force
    }

    while ($true) {
        $ownerToken = [guid]::NewGuid().ToString('N')

        try {
            $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
                throw
            }

            $existingMetadata = Get-LabRunLockMetadata -Path $LockPath
            if ($null -eq $existingMetadata) {
                throw 'PolicyBlocked: active run lock exists'
            }

            $existingHost = [string]$existingMetadata.host
            $existingProcessId = 0
            $processIdParsed = [int]::TryParse([string]$existingMetadata.pid, [ref]$existingProcessId)

            $sameHost = $existingHost.Equals([System.Environment]::MachineName, [System.StringComparison]::OrdinalIgnoreCase)
            if ($sameHost -and $processIdParsed -and -not (Test-LabProcessAlive -ProcessId $existingProcessId)) {
                if (Remove-LabRunLockIfTokenMatches -Path $LockPath -OwnerToken ([string]$existingMetadata.token)) {
                    continue
                }
            }

            throw 'PolicyBlocked: active run lock exists'
        }

        try {
            $hostName = [System.Environment]::MachineName
            $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
            $payload = [pscustomobject]@{
                host = $hostName
                pid = $processId
                token = $ownerToken
                createdAt = [DateTimeOffset]::UtcNow.ToString('o')
            }
            $json = $payload | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $lockStream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $lockStream.Dispose()
        }

        return [pscustomobject]@{
            Path = $LockPath
            OwnerToken = $ownerToken
        }
    }
}
