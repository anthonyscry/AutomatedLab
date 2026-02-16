# Resolve-LabPassword.ps1 -- Shared password resolution logic
function Resolve-LabPassword {
    <#
    .SYNOPSIS
        Resolves the lab admin password from multiple sources with security warnings.
    .DESCRIPTION
        Priority order:
        1. Explicit value (if non-empty)
        2. Environment variable (configurable via -EnvVarName)
        3. Interactive prompt via Read-Host (if running interactively)
        4. Throws an error (non-interactive with no password available)

        When the resolved password matches the default password, emits a security
        warning encouraging the operator to use environment variables or pass
        explicit credentials.

        Callers should pass the current $Password value (which may have been
        set by Lab-Config.ps1 dot-sourcing or by a parameter).
    .PARAMETER Password
        Current password value to validate. Pass $AdminPassword from calling scope.
    .PARAMETER DefaultPassword
        The default password value used in Lab-Config.ps1. Used to detect when
        the operator is unknowingly using a well-known default.
    .PARAMETER EnvVarName
        Name of the environment variable to check. Defaults to OPENCODELAB_ADMIN_PASSWORD.
    .PARAMETER PasswordLabel
        Contextual label for warning messages and interactive prompts.
        Defaults to 'AdminPassword'.
    .OUTPUTS
        [string] The resolved password.
    .EXAMPLE
        $AdminPassword = Resolve-LabPassword -Password $AdminPassword -DefaultPassword 'SimpleLab123!'
    .EXAMPLE
        $SqlSaPassword = Resolve-LabPassword -Password $SqlSaPassword -DefaultPassword 'SimpleLabSqlSa123!' -EnvVarName 'LAB_SQL_SA_PASSWORD' -PasswordLabel 'SqlSaPassword'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Password,
        [string]$DefaultPassword = '',
        [string]$EnvVarName = 'OPENCODELAB_ADMIN_PASSWORD',
        [string]$PasswordLabel = 'AdminPassword'
    )

    $resolvedPassword = ''

    # Priority 1: Explicit non-empty parameter
    if (-not [string]::IsNullOrWhiteSpace($Password)) {
        $resolvedPassword = $Password
    }
    # Priority 2: Environment variable
    elseif (Test-Path env:$EnvVarName) {
        $envValue = [System.Environment]::GetEnvironmentVariable($EnvVarName)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            $resolvedPassword = $envValue
        }
    }

    # Priority 3: Interactive prompt (if no password yet and running interactively)
    if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
        if ([Environment]::UserInteractive) {
            Write-Host "[Security] No $PasswordLabel provided. Prompting interactively..." -ForegroundColor Yellow
            $securePassword = Read-Host -Prompt "Enter $PasswordLabel" -AsSecureString
            # Convert SecureString to plain text (same pattern as LabBuilder/Build-LabFromSelection.ps1:60-62)
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            try {
                $resolvedPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
        }
    }

    # Priority 4: Throw error if still empty
    if ([string]::IsNullOrWhiteSpace($resolvedPassword)) {
        throw "$PasswordLabel is required. Set it in Lab-Config.ps1, pass -$PasswordLabel parameter, or set `$env:$EnvVarName."
    }

    # Warn if resolved password matches the well-known default
    if (-not [string]::IsNullOrWhiteSpace($DefaultPassword) -and $resolvedPassword -eq $DefaultPassword) {
        Write-Warning "[Security] Using default $PasswordLabel ('$DefaultPassword'). Set `$env:$EnvVarName or pass -$PasswordLabel for production use."
    }

    return $resolvedPassword
}
