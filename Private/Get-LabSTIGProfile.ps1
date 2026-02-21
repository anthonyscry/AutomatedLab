function Get-LabSTIGProfile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$OsRole,

        [Parameter(Mandatory)]
        [string]$OsVersionBuild
    )

    # Map OS build prefix to PowerSTIG version year string
    # Keys are major.minor.build prefixes matching Get-WmiObject Win32_OperatingSystem output
    $versionMap = @{
        '10.0.17763' = '2019'   # Windows Server 2019
        '10.0.20348' = '2022'   # Windows Server 2022
    }

    # Normalize role: DC stays DC, everything else is MS (Member Server)
    $stigRole = if ($OsRole -eq 'DC') { 'DC' } else { 'MS' }

    # Find matching OS version by prefix match (handles build.revision format like 10.0.17763.1234)
    $osVersionKey = $null
    foreach ($key in $versionMap.Keys) {
        if ($OsVersionBuild.StartsWith($key)) {
            $osVersionKey = $key
            break
        }
    }

    if (-not $osVersionKey) {
        Write-Warning "[STIGProfile] Unsupported OS version '$OsVersionBuild'. PowerSTIG baselines are available for Server 2019 (10.0.17763) and Server 2022 (10.0.20348)."
        return $null
    }

    $osYear = $versionMap[$osVersionKey]

    return [pscustomobject]@{
        Technology      = 'WindowsServer'
        StigVersion     = $osYear
        OsRole          = $stigRole
        OsVersionString = $OsVersionBuild
    }
}
