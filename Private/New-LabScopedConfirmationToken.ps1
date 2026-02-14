function New-LabScopedConfirmationToken {
    [CmdletBinding()]
    param(
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
        [string]$Secret,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TtlSeconds = 300
    )

    $normalizeHosts = {
        param([string[]]$Hosts)

        return @(
            $Hosts |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
        )
    }

    $toBase64Url = {
        param([byte[]]$Bytes)

        return ([Convert]::ToBase64String($Bytes).TrimEnd('=')).Replace('+', '-').Replace('/', '_')
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

    $issuedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $expiresAt = $issuedAt + [int64]$TtlSeconds
    $normalizedHosts = & $normalizeHosts -Hosts $TargetHosts

    $payload = [ordered]@{
        rid   = $RunId
        hosts = $normalizedHosts
        op    = $OperationHash
        iat   = $issuedAt
        exp   = $expiresAt
    }

    $payloadJson = $payload | ConvertTo-Json -Compress
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes($payloadJson)
    $payloadBase64Url = & $toBase64Url -Bytes $payloadBytes

    $version = 'v1'
    $signingInput = '{0}.{1}' -f $version, $payloadBase64Url
    $signatureBytes = & $computeSignature -InputText $signingInput -SharedSecret $Secret
    $signatureBase64Url = & $toBase64Url -Bytes $signatureBytes

    return '{0}.{1}.{2}' -f $version, $payloadBase64Url, $signatureBase64Url
}
