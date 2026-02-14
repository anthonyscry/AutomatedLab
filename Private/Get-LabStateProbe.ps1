function Get-LabStateProbe {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LabName = 'SimpleLab',

        [Parameter()]
        [string[]]$VMNames = @(),

        [Parameter()]
        [string]$SwitchName = 'LabSwitch',

        [Parameter()]
        [string]$NatName = 'LabNAT'
    )

    $probe = [ordered]@{
        LabRegistered = $false
        MissingVMs = @($VMNames)
        LabReadyAvailable = $false
        SwitchPresent = $false
        NatPresent = $false
    }

    if (Get-Command -Name 'Get-Lab' -ErrorAction SilentlyContinue) {
        try {
            $lab = Get-Lab -Name $LabName -ErrorAction Stop
            $probe.LabRegistered = ($null -ne $lab)
        }
        catch {
            $probe.LabRegistered = $false
        }
    }

    if (Get-Command -Name 'Get-VM' -ErrorAction SilentlyContinue) {
        $missing = @()
        foreach ($vmName in $VMNames) {
            try {
                $null = Get-VM -Name $vmName -ErrorAction Stop
            }
            catch {
                $missing += $vmName
            }
        }
        $probe.MissingVMs = $missing
    }

    if ((Get-Command -Name 'Get-VMSnapshot' -ErrorAction SilentlyContinue) -and $VMNames.Count -gt 0) {
        $labReadyAvailable = $true
        foreach ($vmName in $VMNames) {
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
            $switch = Get-VMSwitch -Name $SwitchName -ErrorAction Stop
            $probe.SwitchPresent = ($null -ne $switch)
        }
        catch {
            $probe.SwitchPresent = $false
        }
    }

    if (Get-Command -Name 'Get-NetNat' -ErrorAction SilentlyContinue) {
        try {
            $nat = Get-NetNat -Name $NatName -ErrorAction Stop
            $probe.NatPresent = ($null -ne $nat)
        }
        catch {
            $probe.NatPresent = $false
        }
    }

    return [pscustomobject]$probe
}
