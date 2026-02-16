function Invoke-LabQuickModeHeal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$StateProbe,

        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter(Mandatory)]
        [string]$GlobalLabConfig.Network.NatName,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$')]
        [string]$GlobalLabConfig.Network.AddressSpace,

        [string[]]$VMNames = @(),

        [int]$TimeoutSeconds = 120,

        [int]$HealthCheckTimeoutSeconds = 60,

        [bool]$Enabled = $true
    )

    $noOp = [pscustomobject]@{
        HealAttempted = $false
        HealSucceeded = $false
        RepairsApplied = @()
        RemainingIssues = @()
        DurationSeconds = 0
    }

    if (-not $Enabled) { return $noOp }

    $props = @($StateProbe.PSObject.Properties.Name)
    $labRegistered = if ($props -contains 'LabRegistered') { [bool]$StateProbe.LabRegistered } else { $false }
    $missingVMs = if ($props -contains 'MissingVMs') { @($StateProbe.MissingVMs) } else { @('unknown') }
    $labReadyAvailable = if ($props -contains 'LabReadyAvailable') { [bool]$StateProbe.LabReadyAvailable } else { $false }
    $switchPresent = if ($props -contains 'SwitchPresent') { [bool]$StateProbe.SwitchPresent } else { $false }
    $natPresent = if ($props -contains 'NatPresent') { [bool]$StateProbe.NatPresent } else { $false }

    if (-not $labRegistered) { return $noOp }
    if ($missingVMs.Count -gt 0) { return $noOp }

    $needsSwitch = -not $switchPresent
    $needsNat = -not $natPresent
    $needsLabReady = -not $labReadyAvailable

    if (-not $needsSwitch -and -not $needsNat -and -not $needsLabReady) { return $noOp }

    $healStart = Get-Date
    $repairs = [System.Collections.Generic.List[string]]::new()
    $remaining = [System.Collections.Generic.List[string]]::new()

    # Possible RepairsApplied: switch_recreated, nat_recreated, labready_created
    # Possible RemainingIssues: switch_repair_failed, nat_repair_failed, labready_unhealable, heal_timeout_exceeded

    if ($needsSwitch) {
        try {
            New-LabSwitch -Name $SwitchName
            $repairs.Add('switch_recreated')
        }
        catch {
            Write-Warning "[AutoHeal] Switch repair failed: $($_.Exception.Message)"
            $remaining.Add('switch_repair_failed')
        }
    }

    if ($needsNat -and ((Get-Date) - $healStart).TotalSeconds -lt $TimeoutSeconds) {
        try {
            New-LabNAT -Name $GlobalLabConfig.Network.NatName -AddressSpace $GlobalLabConfig.Network.AddressSpace
            $repairs.Add('nat_recreated')
        }
        catch {
            Write-Warning "[AutoHeal] NAT repair failed: $($_.Exception.Message)"
            $remaining.Add('nat_repair_failed')
        }
    }
    elseif ($needsNat) {
        $remaining.Add('heal_timeout_exceeded')
    }

    if ($needsLabReady -and ((Get-Date) - $healStart).TotalSeconds -lt $TimeoutSeconds) {
        try {
            # LabReady requires: VMs specified, VMs ready, AND domain healthy
            $healthy = $false
            if ($VMNames.Count -gt 0) {
                Start-LabVMs -VMNames $VMNames -ErrorAction SilentlyContinue
                $ready = Wait-LabVMReady -VMNames $VMNames -TimeoutSeconds $HealthCheckTimeoutSeconds -ErrorAction Stop
                if ($ready) {
                    $healthy = Test-LabDomainHealth -ErrorAction Stop
                }
            }

            if ($healthy) {
                Save-LabReadyCheckpoint
                $repairs.Add('labready_created')
            }
            else {
                $remaining.Add('labready_unhealable')
            }
        }
        catch {
            Write-Warning "[AutoHeal] LabReady repair failed: $($_.Exception.Message)"
            $remaining.Add('labready_unhealable')
        }
    }
    elseif ($needsLabReady) {
        $remaining.Add('heal_timeout_exceeded')
    }

    $duration = [int]((Get-Date) - $healStart).TotalSeconds

    return [pscustomobject]@{
        HealAttempted = $true
        HealSucceeded = ($remaining.Count -eq 0)
        RepairsApplied = @($repairs)
        RemainingIssues = @($remaining)
        DurationSeconds = $duration
    }
}
