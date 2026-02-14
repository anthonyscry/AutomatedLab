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
        if (-not (Test-Path -Path $ProfilePath -PathType Leaf)) {
            throw "Profile path does not exist: $ProfilePath"
        }

        try {
            $profileData = Get-Content -Path $ProfilePath -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Profile file cannot be parsed as a JSON object: $ProfilePath"
        }

        if ($profileData -isnot [pscustomobject]) {
            throw "Profile file cannot be parsed as a JSON object: $ProfilePath"
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
