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

        if (Get-Command -Name 'Get-LabStateProbe' -ErrorAction SilentlyContinue) {
            return Get-LabStateProbe -LabName $ProbeLabName -VMNames $ProbeVMNames -SwitchName $ProbeSwitchName -NatName $ProbeNatName
        }

        $probe = [ordered]@{
            LabRegistered = $false
            MissingVMs = @($ProbeVMNames)
            LabReadyAvailable = $false
            SwitchPresent = $false
            NatPresent = $false
        }

        if (Get-Command -Name 'Get-Lab' -ErrorAction SilentlyContinue) {
            try {
                $lab = Get-Lab -Name $ProbeLabName -ErrorAction Stop
                $probe.LabRegistered = ($null -ne $lab)
            }
            catch {
                $probe.LabRegistered = $false
            }
        }

        if (Get-Command -Name 'Get-VM' -ErrorAction SilentlyContinue) {
            $missing = @()
            foreach ($vmName in $ProbeVMNames) {
                try {
                    $null = Get-VM -Name $vmName -ErrorAction Stop
                }
                catch {
                    $missing += $vmName
                }
            }
            $probe.MissingVMs = $missing
        }

        if ((Get-Command -Name 'Get-VMSnapshot' -ErrorAction SilentlyContinue) -and $ProbeVMNames.Count -gt 0) {
            $labReadyAvailable = $true
            foreach ($vmName in $ProbeVMNames) {
                try {
                    $snapshot = Get-VMSnapshot -VMName $vmName -Name 'LabReady' -ErrorAction Stop
                    if ($null -eq $snapshot) {
                        $labReadyAvailable = $false
                        break
                    }
                }
                catch {
                    $labReadyAvailable = $false
                    break
                }
            }
            $probe.LabReadyAvailable = $labReadyAvailable
        }

        if (Get-Command -Name 'Get-VMSwitch' -ErrorAction SilentlyContinue) {
            try {
                $switch = Get-VMSwitch -Name $ProbeSwitchName -ErrorAction Stop
                $probe.SwitchPresent = ($null -ne $switch)
            }
            catch {
                $probe.SwitchPresent = $false
            }
        }

        if (Get-Command -Name 'Get-NetNat' -ErrorAction SilentlyContinue) {
            try {
                $nat = Get-NetNat -Name $ProbeNatName -ErrorAction Stop
                $probe.NatPresent = ($null -ne $nat)
            }
            catch {
                $probe.NatPresent = $false
            }
        }

        return [pscustomobject]$probe
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
