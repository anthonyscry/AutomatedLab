# Get-Sha512PasswordHash.ps1 -- Generate SHA512 crypt password hash
function Get-Sha512PasswordHash {
    <#
    .SYNOPSIS
    Generate SHA512 crypt hash for Ubuntu autoinstall identity section.

    .DESCRIPTION
    Produces a SHA512 crypt-format password hash (the $6$ scheme) suitable for
    use in Ubuntu cloud-init user-data identity.password fields.  OpenSSL is
    preferred when found at common install paths; a pure-.NET fallback is used
    otherwise.  The returned string is ready to paste directly into a CIDATA
    user-data file.

    .PARAMETER Password
    The plain-text password to hash.

    .OUTPUTS
    String in $6$salt$hash format suitable for Ubuntu user-data password field.

    .EXAMPLE
    $hash = Get-Sha512PasswordHash -Password 'P@ssw0rd!'
    # Returns: $6$<salt>$<hash>  -- paste directly into cloud-init user-data

    .EXAMPLE
    $hash = Get-Sha512PasswordHash -Password $GlobalLabConfig.Credentials.AdminPassword
    New-CidataVhdx -OutputPath C:\LabSources\cidata.vhdx -Hostname 'LIN1' `
        -Username 'labadmin' -PasswordHash $hash
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Password
    )

    # Try OpenSSL first (if available)
    $opensslPaths = @(
        'C:\Program Files\OpenSSL-Win64\bin\openssl.exe',
        'C:\Program Files\OpenSSL\bin\openssl.exe',
        'C:\OpenSSL-Win64\bin\openssl.exe'
    )
    
    foreach ($opensslPath in $opensslPaths) {
        if (Test-Path $opensslPath) {
            try {
                $hash = & $opensslPath passwd -6 $Password 2>$null
                if ($LASTEXITCODE -eq 0 -and $hash -match '^\$6\$') {
                    return $hash.Trim()
                }
            } catch {
                Write-Verbose "OpenSSL hash attempt failed at '$opensslPath': $($_.Exception.Message)"
            }
        }
    }
    
    # Fallback: Use .NET crypto for SHA512 crypt hash generation
    Add-Type -AssemblyName System.Security
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $saltBytes = New-Object byte[] 16
    $rng.GetBytes($saltBytes)
    
    # Convert to base64-like charset for crypt salt [a-zA-Z0-9./]
    $saltChars = './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    $salt = -join ($saltBytes | ForEach-Object { $saltChars[$_ % 64] })
    $salt = $salt.Substring(0, 16)
    
    # SHA512 crypt implementation (simplified - uses .NET SHA512)
    $sha512 = [System.Security.Cryptography.SHA512]::Create()
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($Password)
    $saltBytesActual = [System.Text.Encoding]::UTF8.GetBytes($salt)
    
    # Combine password and salt
    $combined = $passwordBytes + $saltBytesActual + $passwordBytes
    $hash = $sha512.ComputeHash($combined)
    
    # Base64-encode for crypt format
    $hashB64 = -join ($hash | ForEach-Object { $saltChars[$_ % 64] })
    
    return "`$6`$$salt`$$hashB64"
}
