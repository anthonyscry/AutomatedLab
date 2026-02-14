function Get-LabFleetStateProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$HostNames,

        [Parameter()]
        [string]$LabName = 'SimpleLab',

        [Parameter()]
        [string[]]$VMNames = @(),

        [Parameter()]
        [string]$SwitchName = 'LabSwitch',

        [Parameter()]
        [string]$NatName = 'LabNAT'
    )

    $results = @()
    $probeScriptBlock = {
        param($ProbeLabName, $ProbeVMNames, $ProbeSwitchName, $ProbeNatName)

        Get-LabStateProbe -LabName $ProbeLabName -VMNames $ProbeVMNames -SwitchName $ProbeSwitchName -NatName $ProbeNatName
    }

    foreach ($hostName in $HostNames) {
        try {
            $probe = Invoke-LabRemoteProbe -HostName $hostName -ScriptBlock $probeScriptBlock -ArgumentList @($LabName, $VMNames, $SwitchName, $NatName)
            $results += [pscustomobject]@{
                HostName = $hostName
                Reachable = $true
                Probe = $probe
                Failure = $null
            }
        }
        catch {
            $results += [pscustomobject]@{
                HostName = $hostName
                Reachable = $false
                Probe = $null
                Failure = $_.Exception.Message
            }
        }
    }

    return @($results)
}
