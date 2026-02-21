function Save-LabProfile {
    <#
    .SYNOPSIS
        Saves a lab configuration snapshot as a named profile to .planning/profiles/{Name}.json.
    .PARAMETER Name
        Profile name (used as filename, must be filesystem-safe: alphanumeric, hyphens, underscores).
    .PARAMETER Config
        Hashtable containing the lab configuration to snapshot (e.g., $GlobalLabConfig).
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .PARAMETER Description
        Human-readable description of the profile.
    .OUTPUTS
        PSCustomObject with Success and Message properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter()]
        [string]$Description = ''
    )

    # Validate profile name is filesystem-safe (prevent path traversal and invalid filenames)
    if ($Name -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Profile validation failed: Profile name '$Name' contains invalid characters. Use only letters, numbers, hyphens, and underscores."
    }

    # Count VMs from config for summary display
    $vmCount = 0
    if ($Config.ContainsKey('Lab') -and $Config.Lab -is [hashtable] -and $Config.Lab.ContainsKey('CoreVMNames')) {
        $vmCount = @($Config.Lab.CoreVMNames).Count
    }

    # Count Linux VMs from Builder.VMNames or presence of Builder.LinuxVM section
    $linuxVmCount = 0
    if ($Config.ContainsKey('Builder') -and $Config.Builder -is [hashtable]) {
        if ($Config.Builder.ContainsKey('VMNames') -and $Config.Builder.VMNames -is [hashtable]) {
            $linuxKeys = @('Ubuntu', 'WebServerUbuntu', 'DatabaseUbuntu', 'DockerUbuntu', 'K8sUbuntu')
            $linuxVmCount = @($linuxKeys | Where-Object { $Config.Builder.VMNames.ContainsKey($_) }).Count
        }
        elseif ($Config.Builder.ContainsKey('LinuxVM') -and $Config.Builder.LinuxVM -is [hashtable]) {
            $linuxVmCount = 1  # LinuxVM config present but no VMNames — at least one Linux VM
        }
    }

    # Build profile object with metadata
    $profile = [ordered]@{
        name         = $Name
        description  = $Description
        createdAt    = Get-Date -Format 'o'
        vmCount      = $vmCount
        linuxVmCount = $linuxVmCount
        config       = $Config
    }

    # Ensure profiles directory exists
    $profilesDir = Join-Path (Join-Path $RepoRoot '.planning') 'profiles'
    if (-not (Test-Path $profilesDir)) {
        $null = New-Item -ItemType Directory -Path $profilesDir -Force
        Write-Verbose "Created directory: $profilesDir"
    }

    $profilePath = Join-Path $profilesDir "$Name.json"

    try {
        $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $profilePath -Encoding UTF8
        return [pscustomobject]@{
            Success = $true
            Message = "Profile '$Name' saved successfully."
        }
    }
    catch {
        throw "Failed to save profile to '$profilePath': $_"
    }
}
