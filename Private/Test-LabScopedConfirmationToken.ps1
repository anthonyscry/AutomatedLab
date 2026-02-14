function Test-LabScopedConfirmationToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$TargetHosts,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OperationHash,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Secret
    )

    $result = [PSCustomObject]@{
        Valid  = $false
        Reason = 'invalid'
    }

    $normalizeHosts = {
        param([string[]]$Hosts)

        return @(
            $Hosts |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
        )
    }

    $fromBase64Url = {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) {
            throw 'empty_base64url'
        }

        $base64 = $Text.Replace('-', '+').Replace('_', '/')
        switch ($base64.Length % 4) {
            2 { $base64 += '==' }
            3 { $base64 += '=' }
            0 { }
            default { throw 'invalid_base64url_length' }
        }

        return [Convert]::FromBase64String($base64)
    }

    $computeSignature = {
        param([string]$InputText, [string]$SharedSecret)

        $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($SharedSecret))
        try {
            return $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($InputText))
        }
        finally {
            $hmac.Dispose()
        }
    }

    $fixedTimeEquals = {
        param([byte[]]$Left, [byte[]]$Right)

        if ($null -eq $Left -or $null -eq $Right) {
            return $false
        }

        if ($Left.Length -ne $Right.Length) {
            return $false
        }

        $diff = 0
        for ($i = 0; $i -lt $Left.Length; $i++) {
            $diff = $diff -bor ($Left[$i] -bxor $Right[$i])
        }

        return ($diff -eq 0)
    }

    $parts = $Token -split '\.'
    if ($parts.Count -ne 3 -or $parts[0] -ne 'v1') {
        $result.Reason = 'malformed_token'
        return $result
    }

    $payloadBytes = $null
    $signatureBytes = $null

    try {
        $payloadBytes = [byte[]](& $fromBase64Url -Text $parts[1])
        $signatureBytes = [byte[]](& $fromBase64Url -Text $parts[2])
    }
    catch {
        $result.Reason = 'malformed_token'
        return $result
    }

    $expectedSignature = & $computeSignature -InputText ('{0}.{1}' -f $parts[0], $parts[1]) -SharedSecret $Secret
    if (-not (& $fixedTimeEquals -Left $signatureBytes -Right ([byte[]]$expectedSignature))) {
        $result.Reason = 'bad_signature'
        return $result
    }

    $payload = $null
    try {
        $payloadJson = [Text.Encoding]::UTF8.GetString($payloadBytes)
        $payload = $payloadJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $result.Reason = 'malformed_token'
        return $result
    }

    if (
        -not $payload.PSObject.Properties.Name.Contains('rid') -or
        -not $payload.PSObject.Properties.Name.Contains('hosts') -or
        -not $payload.PSObject.Properties.Name.Contains('op') -or
        -not $payload.PSObject.Properties.Name.Contains('exp')
    ) {
        $result.Reason = 'malformed_token'
        return $result
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $expiresAt = 0
    if (-not [int64]::TryParse([string]$payload.exp, [ref]$expiresAt)) {
        $result.Reason = 'malformed_token'
        return $result
    }

    if ($now -ge $expiresAt) {
        $result.Reason = 'token_expired'
        return $result
    }

    if ([string]$payload.rid -cne $RunId) {
        $result.Reason = 'run_scope_mismatch'
        return $result
    }

    $tokenHosts = & $normalizeHosts -Hosts ([string[]]$payload.hosts)
    $expectedHosts = & $normalizeHosts -Hosts $TargetHosts
    $tokenHostsJoined = ([string[]]$tokenHosts) -join ','
    $expectedHostsJoined = ([string[]]$expectedHosts) -join ','
    if ($tokenHostsJoined -cne $expectedHostsJoined) {
        $result.Reason = 'host_scope_mismatch'
        return $result
    }

    if ([string]$payload.op -cne $OperationHash) {
        $result.Reason = 'operation_scope_mismatch'
        return $result
    }

    $result.Valid = $true
    $result.Reason = 'valid'
    return $result
}
