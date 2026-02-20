function Remove-LabProfile {
    <#
    .SYNOPSIS
        Deletes a named lab profile from .planning/profiles/{Name}.json.
    .PARAMETER Name
        Profile name to remove (must be filesystem-safe: alphanumeric, hyphens, underscores).
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .OUTPUTS
        PSCustomObject with Success and Message properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    # Validate name to prevent path traversal
    if ($Name -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Profile validation failed: Profile name '$Name' contains invalid characters. Use only letters, numbers, hyphens, and underscores."
    }

    $profilePath = Join-Path (Join-Path (Join-Path $RepoRoot '.planning') 'profiles') "$Name.json"

    if (-not (Test-Path $profilePath)) {
        throw "Profile '$Name' not found."
    }

    try {
        Remove-Item -Path $profilePath -Force
        return [pscustomobject]@{
            Success = $true
            Message = "Profile '$Name' removed successfully."
        }
    }
    catch {
        throw "Failed to remove profile '$Name': $_"
    }
}
