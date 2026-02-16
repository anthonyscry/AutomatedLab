# Resolve-LabSqlPassword.ps1 -- SQL SA password resolution wrapper
function Resolve-LabSqlPassword {
    <#
    .SYNOPSIS
        Resolves the SQL SA password using the same resolution chain as Resolve-LabPassword.
    .DESCRIPTION
        Thin wrapper around Resolve-LabPassword configured for SQL SA password:
        - Uses LAB_ADMIN_PASSWORD environment variable (same as LabBuilder)
        - Default password is 'SimpleLabSqlSa123!'
        - Label is 'SqlSaPassword' for contextual warnings
    .PARAMETER Password
        Current SQL SA password value to validate.
    .OUTPUTS
        [string] The resolved SQL SA password.
    .EXAMPLE
        $SqlSaPassword = Resolve-LabSqlPassword -Password $SqlSaPassword
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Password
    )

    # Use the BuilderPasswordEnvVar from config (LAB_ADMIN_PASSWORD)
    # This keeps SQL password aligned with LabBuilder's password source
    $envVarName = if (Test-Path variable:GlobalLabConfig) {
        $GlobalLabConfig.Credentials.BuilderPasswordEnvVar
    } else {
        'LAB_ADMIN_PASSWORD'
    }

    Resolve-LabPassword -Password $Password `
        -DefaultPassword 'SimpleLabSqlSa123!' `
        -EnvVarName $envVarName `
        -PasswordLabel 'SqlSaPassword'
}
