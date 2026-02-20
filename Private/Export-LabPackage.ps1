function Export-LabPackage {
    <#
    .SYNOPSIS
        Exports a saved lab profile as a self-contained JSON package with version and metadata.
    .DESCRIPTION
        Reads a named profile from .planning/profiles/{Name}.json and bundles it into a portable
        JSON package containing version info, timestamps, source metadata, and the full lab
        configuration. The package can be transferred to another host and imported with
        Import-LabPackage.
    .PARAMETER Name
        Profile name to export (must be filesystem-safe: alphanumeric, hyphens, underscores).
    .PARAMETER Path
        Output directory where the package JSON file will be written.
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .OUTPUTS
        PSCustomObject with Success, Message, and Path properties.
    .EXAMPLE
        Export-LabPackage -Name 'my-lab' -Path 'C:\Packages' -RepoRoot 'C:\AutomatedLab'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    # Validate profile name is filesystem-safe (prevent path traversal and invalid filenames)
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
        throw "Failed to read profile '$Name': $($_.Exception.Message)"
    }

    # Extract source description (default to empty string if missing)
    $sourceDescription = ''
    if ($data -is [System.Management.Automation.PSCustomObject]) {
        $hasDescription = $null -ne ($data | Get-Member -Name 'description' -MemberType NoteProperty)
        if ($hasDescription) {
            $sourceDescription = $data.description
        }
    }

    # Build package object with metadata
    $package = [ordered]@{
        packageVersion    = '1.0'
        exportedAt        = Get-Date -Format 'o'
        sourceName        = $data.name
        sourceDescription = $sourceDescription
        config            = $data.config
    }

    # Ensure output directory exists
    if (-not (Test-Path $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
        Write-Verbose "Created directory: $Path"
    }

    $packagePath = Join-Path $Path "$Name.json"

    try {
        $package | ConvertTo-Json -Depth 10 | Set-Content -Path $packagePath -Encoding UTF8
        return [pscustomobject]@{
            Success = $true
            Message = "Package '$Name' exported to '$packagePath'."
            Path    = $packagePath
        }
    }
    catch {
        throw "Failed to write package to '$packagePath': $($_.Exception.Message)"
    }
}
