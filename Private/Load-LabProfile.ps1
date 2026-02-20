function Load-LabProfile {
    <#
    .SYNOPSIS
        Loads a named lab profile from .planning/profiles/{Name}.json and returns the config as a hashtable.
    .DESCRIPTION
        Reads the profile JSON, validates it contains a 'config' key, converts the PSCustomObject back to
        a nested hashtable, and returns it ready for assignment to $GlobalLabConfig.
        The function does NOT modify global state directly — the caller is responsible for assigning the result.
    .PARAMETER Name
        Profile name to load (must be filesystem-safe: alphanumeric, hyphens, underscores).
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .OUTPUTS
        [hashtable] The lab configuration hashtable loaded from the profile.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    # Validate profile name is filesystem-safe (prevents path traversal and invalid filenames)
    if ($Name -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Profile validation failed: Profile name '$Name' contains invalid characters. Use only letters, numbers, hyphens, and underscores."
    }

    # Build profile path using nested Join-Path for PS 5.1 compatibility (only 2 args per call)
    $profilePath = Join-Path (Join-Path (Join-Path $RepoRoot '.planning') 'profiles') "$Name.json"

    if (-not (Test-Path $profilePath)) {
        throw "Profile '$Name' not found."
    }

    try {
        $raw = Get-Content -Path $profilePath -Raw -Encoding UTF8 -ErrorAction Stop
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to load profile '$Name': $($_.Exception.Message)"
    }

    # Validate the profile contains a 'config' key
    $hasConfig = $false
    if ($data -is [System.Management.Automation.PSCustomObject]) {
        $hasConfig = $null -ne ($data | Get-Member -Name 'config' -MemberType NoteProperty)
    }
    if (-not $hasConfig) {
        throw "Profile '$Name' is malformed: missing 'config' key."
    }

    # Convert PSCustomObject back to a nested hashtable
    # ConvertFrom-Json returns PSCustomObject but $GlobalLabConfig expects hashtable
    return ConvertTo-Hashtable $data.config
}

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
        Recursively converts a PSCustomObject (from ConvertFrom-Json) to a nested hashtable.
    .PARAMETER InputObject
        The object to convert. PSCustomObjects are converted to hashtables, arrays are iterated,
        and leaf values are passed through unchanged.
    #>
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-Hashtable $property.Value
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ConvertTo-Hashtable $item
        }
        return $list
    }

    return $InputObject
}
