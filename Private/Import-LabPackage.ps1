function Import-LabPackage {
    <#
    .SYNOPSIS
        Imports a lab package JSON and saves it as a named profile. Validates all required
        fields before any configuration is applied.
    .DESCRIPTION
        Reads a self-contained package JSON file (produced by Export-LabPackage), validates
        that all required fields are present (packageVersion, sourceName, config, config.Lab),
        converts the config from PSCustomObject to hashtable, and saves it as a profile via
        Save-LabProfile. Validation collects ALL errors before throwing, so the operator sees
        every issue at once rather than fixing them one at a time.
    .PARAMETER Path
        Full path to the package JSON file to import.
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .PARAMETER Name
        Optional override name for the imported profile. If not provided, uses the sourceName
        from the package.
    .OUTPUTS
        PSCustomObject with Success, Message, and ProfileName properties.
    .EXAMPLE
        Import-LabPackage -Path 'C:\Packages\my-lab.json' -RepoRoot 'C:\AutomatedLab'
    .EXAMPLE
        Import-LabPackage -Path 'C:\Packages\my-lab.json' -RepoRoot 'C:\AutomatedLab' -Name 'renamed-lab'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter()]
        [string]$Name
    )

    # Validate package file exists
    if (-not (Test-Path $Path)) {
        throw "Package file not found: '$Path'"
    }

    # Read and parse the package JSON
    try {
        $raw = Get-Content -Raw -Path $Path -Encoding UTF8 -ErrorAction Stop
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to read package '$Path': $($_.Exception.Message)"
    }

    # Validate package integrity — collect ALL errors before throwing (XFER-03)
    $validationErrors = @()

    $hasPackageVersion = ($data -is [System.Management.Automation.PSCustomObject]) -and
        ($null -ne ($data | Get-Member -Name 'packageVersion' -MemberType NoteProperty))
    if (-not $hasPackageVersion) {
        $validationErrors += "Missing required field: 'packageVersion'"
    }

    $hasSourceName = ($data -is [System.Management.Automation.PSCustomObject]) -and
        ($null -ne ($data | Get-Member -Name 'sourceName' -MemberType NoteProperty))
    if (-not $hasSourceName) {
        $validationErrors += "Missing required field: 'sourceName'"
    }

    $hasConfig = ($data -is [System.Management.Automation.PSCustomObject]) -and
        ($null -ne ($data | Get-Member -Name 'config' -MemberType NoteProperty))
    if (-not $hasConfig) {
        $validationErrors += "Missing required field: 'config'"
    }

    # Check config.Lab only if config exists
    if ($hasConfig) {
        $configObj = $data.config
        $hasLab = ($configObj -is [System.Management.Automation.PSCustomObject]) -and
            ($null -ne ($configObj | Get-Member -Name 'Lab' -MemberType NoteProperty))
        if (-not $hasLab) {
            $validationErrors += "Package config missing required section: 'Lab'"
        }
    }

    if ($validationErrors.Count -gt 0) {
        throw "Package validation failed:`n$($validationErrors -join "`n")"
    }

    # Determine profile name: use $Name override if provided, else sourceName from package
    $resolvedName = if ($PSBoundParameters.ContainsKey('Name') -and $Name -ne '') { $Name } else { $data.sourceName }

    # Validate resolved name is filesystem-safe
    if ($resolvedName -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Profile validation failed: Profile name '$resolvedName' contains invalid characters. Use only letters, numbers, hyphens, and underscores."
    }

    # Convert PSCustomObject config to hashtable for Save-LabProfile
    $configHashtable = ConvertTo-PackageHashtable $data.config

    # Save as profile via Save-LabProfile (suppress output to avoid polluting pipeline)
    $null = Save-LabProfile -Name $resolvedName -Config $configHashtable -RepoRoot $RepoRoot -Description "Imported from package: $($data.sourceName)"

    return [pscustomobject]@{
        Success     = $true
        Message     = "Package imported as profile '$resolvedName'."
        ProfileName = $resolvedName
    }
}

function ConvertTo-PackageHashtable {
    <#
    .SYNOPSIS
        Recursively converts a PSCustomObject (from ConvertFrom-Json) to a nested hashtable.
    .DESCRIPTION
        Named ConvertTo-PackageHashtable to avoid conflicts with the ConvertTo-Hashtable
        function in Load-LabProfile.ps1. Same implementation, different name.
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
            $result[$property.Name] = ConvertTo-PackageHashtable $property.Value
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ConvertTo-PackageHashtable $item
        }
        return $list
    }

    return $InputObject
}
