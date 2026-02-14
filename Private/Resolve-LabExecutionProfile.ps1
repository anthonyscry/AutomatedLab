function Resolve-LabExecutionProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('deploy', 'teardown')]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$Mode,

        [Parameter()]
        [string]$ProfilePath,

        [Parameter()]
        [hashtable]$Overrides
    )

    $effective = @{}

    if ($Mode -eq 'quick') {
        $effective.Mode = 'quick'
        $effective.ReuseLabDefinition = $true
        $effective.ReuseInfra = $true
        $effective.SkipHeavyValidation = $true
        $effective.ParallelChecks = $true
        $effective.DestructiveCleanup = $false
    }
    else {
        $effective.Mode = 'full'
        $effective.ReuseLabDefinition = $false
        $effective.ReuseInfra = $false
        $effective.SkipHeavyValidation = $false
        $effective.ParallelChecks = $true
        $effective.DestructiveCleanup = ($Operation -eq 'teardown')
    }

    if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
        if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
            throw "Profile file could not be read: $ProfilePath"
        }

        try {
            $profileContent = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop
        }
        catch {
            throw "Profile file could not be read: $ProfilePath"
        }

        try {
            $profileData = $profileContent | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Profile file contains invalid JSON: $ProfilePath"
        }

        if ($profileData -isnot [pscustomobject]) {
            throw "Profile file contains invalid JSON: $ProfilePath"
        }

        foreach ($property in $profileData.PSObject.Properties) {
            $effective[$property.Name] = $property.Value
        }
    }

    if ($null -ne $Overrides) {
        foreach ($key in $Overrides.Keys) {
            $effective[$key] = $Overrides[$key]
        }
    }

    return [pscustomobject]$effective
}
