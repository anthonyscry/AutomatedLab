function Invoke-LabTTLMonitor {
    <#
    .SYNOPSIS
        Checks TTL thresholds and suspends/stops lab VMs on expiry.

    .DESCRIPTION
        Called by the OpenCodeLab-TTLMonitor scheduled task every 5 minutes.
        Checks wall-clock and idle thresholds. When either expires, applies
        the configured action (Save-VM or Stop-VM) to all running lab VMs.
        Writes state to lab-ttl-state.json after each check.

    .PARAMETER StatePath
        Path to the TTL state JSON file. Defaults to .planning/lab-ttl-state.json.

    .PARAMETER LabStartTime
        Override lab start time for testability. Defaults to reading from state JSON
        or current time if no prior state exists.

    .OUTPUTS
        PSCustomObject with TTLExpired, ActionAttempted, ActionSucceeded,
        VMsProcessed, RemainingIssues, DurationSeconds fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$StatePath,

        [datetime]$LabStartTime
    )

    $noOp = [pscustomobject]@{
        TTLExpired      = $false
        ActionAttempted = 'None'
        ActionSucceeded = $false
        VMsProcessed    = @()
        RemainingIssues = @()
        DurationSeconds = 0
    }

    # Determine state path
    if (-not $StatePath) {
        $planningDir = Join-Path (Join-Path $PSScriptRoot '..') '.planning'
        $StatePath = Join-Path $planningDir 'lab-ttl-state.json'
    }

    $config = Get-LabTTLConfig

    if (-not $config.Enabled) {
        Write-Verbose "[TTLMonitor] TTL monitoring is disabled"
        return $noOp
    }

    # Get lab VMs
    $allVMs = @(Get-VM -ErrorAction SilentlyContinue)
    if ($allVMs.Count -eq 0) {
        Write-Verbose "[TTLMonitor] No VMs found"
        return $noOp
    }

    $monitorStart = Get-Date

    # Determine lab start time
    $startTime = if ($PSBoundParameters.ContainsKey('LabStartTime')) {
        $LabStartTime
    } else {
        # Try reading from cached state
        $cachedStart = $null
        if (Test-Path $StatePath) {
            try {
                $raw = Get-Content -Path $StatePath -Raw -ErrorAction SilentlyContinue
                if ($raw) {
                    $cached = $raw | ConvertFrom-Json
                    if ($cached.StartTime) {
                        $cachedStart = [datetime]$cached.StartTime
                    }
                }
            }
            catch { <# ignore parse errors #> }
        }
        if ($cachedStart) { $cachedStart } else { Get-Date }
    }

    # Check wall-clock expiry
    $elapsed = (Get-Date) - $startTime
    $wallClockExpired = ($config.WallClockHours -gt 0) -and ($elapsed.TotalHours -ge $config.WallClockHours)

    # Check idle expiry (all running VMs have been up beyond IdleMinutes threshold)
    $idleExpired = $false
    if ($config.IdleMinutes -gt 0) {
        $runningVMs = @($allVMs | Where-Object { $_.State -eq 'Running' })
        if ($runningVMs.Count -gt 0) {
            $allIdle = $true
            foreach ($vm in $runningVMs) {
                if ($vm.Uptime.TotalMinutes -lt $config.IdleMinutes) {
                    $allIdle = $false
                    break
                }
            }
            $idleExpired = $allIdle
        }
    }

    # Either trigger causes expiry
    $expired = $wallClockExpired -or $idleExpired

    $processed = [System.Collections.Generic.List[string]]::new()
    $remaining = [System.Collections.Generic.List[string]]::new()
    $actionName = $config.Action

    if ($expired) {
        if ($wallClockExpired) {
            Write-Warning "[TTLMonitor] Wall-clock TTL expired (elapsed: $([math]::Round($elapsed.TotalHours, 1))h, limit: $($config.WallClockHours)h)"
        }
        if ($idleExpired) {
            Write-Warning "[TTLMonitor] Idle TTL expired (all VMs idle beyond $($config.IdleMinutes) minutes)"
        }

        $runningVMs = @($allVMs | Where-Object { $_.State -eq 'Running' })

        foreach ($vm in $runningVMs) {
            try {
                if ($actionName -eq 'Suspend') {
                    Save-VM -Name $vm.Name -ErrorAction Stop
                }
                else {
                    Stop-VM -Name $vm.Name -Force -ErrorAction Stop
                }
                $processed.Add($vm.Name)
            }
            catch {
                Write-Warning "[TTLMonitor] Failed to $actionName VM '$($vm.Name)': $($_.Exception.Message)"
                $remaining.Add("$($vm.Name)_action_failed")
            }
        }
    }
    else {
        Write-Verbose "[TTLMonitor] TTL check OK (elapsed: $([math]::Round($elapsed.TotalHours, 1))h)"
        $actionName = 'None'
    }

    # Build VM states hashtable
    $vmStates = @{}
    foreach ($vm in $allVMs) {
        $vmStates[$vm.Name] = [string]$vm.State
    }

    # Get lab name
    $labName = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('Lab') -and $GlobalLabConfig.Lab.ContainsKey('Name')) {
            $GlobalLabConfig.Lab.Name
        } else { 'Lab' }
    } else { 'Lab' }

    # Write state JSON
    $state = @{
        LabName     = $labName
        LastChecked = (Get-Date).ToString('o')
        StartTime   = $startTime.ToString('o')
        TTLExpired  = $expired
        VMStates    = $vmStates
    }
    $stateJson = $state | ConvertTo-Json -Depth 3
    Set-Content -Path $StatePath -Value $stateJson -Encoding UTF8

    $duration = [int]((Get-Date) - $monitorStart).TotalSeconds

    return [pscustomobject]@{
        TTLExpired      = $expired
        ActionAttempted = $actionName
        ActionSucceeded = ($expired -and $remaining.Count -eq 0)
        VMsProcessed    = @($processed)
        RemainingIssues = @($remaining)
        DurationSeconds = $duration
    }
}
