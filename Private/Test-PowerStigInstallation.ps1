function Test-PowerStigInstallation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [version]$MinimumVersion = '4.28.0'
    )

    $requiredModules = @('PowerSTIG')
    $keyDependencies = @(
        'AuditPolicyDsc',
        'SecurityPolicyDsc',
        'WindowsDefenderDsc',
        'xDnsServer',
        'xWebAdministration',
        'ProcessMitigations',
        'PSDscResources',
        'GPRegistryPolicyParser',
        'FileContentDsc',
        'CertificateDsc'
    )

    try {
        $remoteResult = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($modules, $deps, $minVer)
            $result = @{ Modules = @{}; Missing = [System.Collections.Generic.List[string]]::new() }
            foreach ($mod in $modules) {
                $found = Get-Module -Name $mod -ListAvailable -ErrorAction SilentlyContinue |
                         Sort-Object Version -Descending | Select-Object -First 1
                if ($found -and $found.Version -ge [version]$minVer) {
                    $result.Modules[$mod] = $found.Version.ToString()
                } else {
                    $result.Missing.Add($mod)
                }
            }
            foreach ($dep in $deps) {
                $found = Get-Module -Name $dep -ListAvailable -ErrorAction SilentlyContinue
                if (-not $found) { $result.Missing.Add($dep) }
            }
            $result
        } -ArgumentList @($requiredModules, $keyDependencies, $MinimumVersion.ToString())

        $missingList = @($remoteResult.Missing)
        $installed = $missingList.Count -eq 0

        $version = $null
        if ($remoteResult.Modules.ContainsKey('PowerSTIG')) {
            $version = $remoteResult.Modules['PowerSTIG']
        }

        return [pscustomobject]@{
            Installed      = $installed
            Version        = $version
            MissingModules = $missingList
            ComputerName   = $ComputerName
        }
    }
    catch {
        Write-Warning "[PowerSTIG] Pre-flight check failed on ${ComputerName}: $($_.Exception.Message)"
        return [pscustomobject]@{
            Installed      = $false
            Version        = $null
            MissingModules = @('PowerSTIG (check failed)')
            ComputerName   = $ComputerName
        }
    }
}
