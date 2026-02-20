function Get-LabProfile {
    <#
    .SYNOPSIS
        Lists all saved lab profiles or retrieves a single profile by name.
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .PARAMETER Name
        If provided, retrieves the single named profile. If omitted, lists all profiles.
    .OUTPUTS
        PSCustomObject[] with Name, Description, VMCount, CreatedAt, and Path properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter()]
        [string]$Name
    )

    $profilesDir = Join-Path (Join-Path $RepoRoot '.planning') 'profiles'

    # Single profile retrieval by name
    if ($PSBoundParameters.ContainsKey('Name') -and $Name -ne '') {
        $profilePath = Join-Path $profilesDir "$Name.json"
        if (-not (Test-Path $profilePath)) {
            throw "Profile '$Name' not found."
        }
        try {
            $raw = Get-Content -Path $profilePath -Raw -Encoding UTF8
            return $raw | ConvertFrom-Json
        }
        catch {
            throw "Failed to read profile '$Name': $_"
        }
    }

    # List all profiles
    if (-not (Test-Path $profilesDir)) {
        return @()
    }

    $profileFiles = @(Get-ChildItem -Path $profilesDir -Filter '*.json' -ErrorAction SilentlyContinue)
    if ($profileFiles.Count -eq 0) {
        return @()
    }

    $results = @()
    foreach ($file in $profileFiles) {
        try {
            $raw = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            $data = $raw | ConvertFrom-Json
            $results += [pscustomobject]@{
                Name        = $data.name
                Description = $data.description
                VMCount     = $data.vmCount
                CreatedAt   = $data.createdAt
                Path        = $file.FullName
            }
        }
        catch {
            Write-Warning "Skipping corrupt profile file '$($file.Name)': $_"
        }
    }

    # Sort newest first
    return @($results | Sort-Object -Property CreatedAt -Descending)
}
