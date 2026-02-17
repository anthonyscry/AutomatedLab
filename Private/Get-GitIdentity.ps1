# Get-GitIdentity.ps1 -- Resolve git name/email identity values
function Get-GitIdentity {
    [CmdletBinding()]
    param([string]$DefaultName, [string]$DefaultEmail)

    try {
        $name  = $DefaultName
        $email = $DefaultEmail

        if ([string]::IsNullOrWhiteSpace($name))  { $name  = Read-Host "  Git user.name (e.g. Anthony Tran)" }
        if ([string]::IsNullOrWhiteSpace($email)) { $email = Read-Host "  Git user.email (e.g. you@domain)" }

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($email)) {
            throw "Git identity is required."
        }

        return @{ Name = $name; Email = $email }
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Get-GitIdentity: failed to retrieve git identity - $_", $_.Exception),
                'Get-GitIdentity.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}
