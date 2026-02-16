function Protect-LabLogString {
    <#
    .SYNOPSIS
        Scrubs known credential patterns from a string.
    .DESCRIPTION
        Replaces known default passwords, environment variable password values,
        and credential-like patterns with '***REDACTED***' to prevent credential
        leakage in logs, run artifacts, and error output.
    .PARAMETER InputString
        The string to scrub.
    .OUTPUTS
        [string] The scrubbed string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()]
        [string]$InputString
    )

    if ([string]::IsNullOrEmpty($InputString)) { return $InputString }

    $result = $InputString

    # Scrub known default passwords
    $knownDefaults = @('SimpleLab123!', 'SimpleLabSqlSa123!')
    foreach ($pwd in $knownDefaults) {
        if ($result.Contains($pwd)) {
            $result = $result.Replace($pwd, '***REDACTED***')
        }
    }

    # Scrub password env var values if they are set
    $envVarNames = @('OPENCODELAB_ADMIN_PASSWORD', 'LAB_ADMIN_PASSWORD')
    foreach ($envName in $envVarNames) {
        $envValue = [System.Environment]::GetEnvironmentVariable($envName)
        if (-not [string]::IsNullOrEmpty($envValue) -and $result.Contains($envValue)) {
            $result = $result.Replace($envValue, '***REDACTED***')
        }
    }

    # Scrub GlobalLabConfig passwords if available
    if (Test-Path variable:GlobalLabConfig) {
        $configPasswords = @(
            $GlobalLabConfig.Credentials.AdminPassword,
            $GlobalLabConfig.Credentials.SqlSaPassword
        )
        foreach ($cp in $configPasswords) {
            if (-not [string]::IsNullOrEmpty($cp) -and $result.Contains($cp)) {
                $result = $result.Replace($cp, '***REDACTED***')
            }
        }
    }

    return $result
}
