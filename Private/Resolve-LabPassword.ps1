# Resolve-LabPassword.ps1 -- Shared password resolution logic
function Resolve-LabPassword {
    <#
    .SYNOPSIS
        Resolves the lab admin password from multiple sources.
    .DESCRIPTION
        Priority order:
        1. Explicit value (if non-empty)
        2. Environment variable OPENCODELAB_ADMIN_PASSWORD
        3. Throws an error

        Callers should pass the current $AdminPassword value (which may have been
        set by Lab-Config.ps1 dot-sourcing or by a -AdminPassword param).
    .PARAMETER Password
        Current password value to validate. Pass $AdminPassword from calling scope.
    .OUTPUTS
        [string] The resolved password.
    .EXAMPLE
        $AdminPassword = Resolve-LabPassword -Password $AdminPassword
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Password
    )

    if (-not [string]::IsNullOrWhiteSpace($Password)) {
        return $Password
    }

    if ($env:OPENCODELAB_ADMIN_PASSWORD) {
        return $env:OPENCODELAB_ADMIN_PASSWORD
    }

    throw "AdminPassword is required. Set it in Lab-Config.ps1, pass -AdminPassword, or set `$env:OPENCODELAB_ADMIN_PASSWORD."
}
