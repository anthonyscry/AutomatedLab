function Get-LabUptime {
    <#
    .SYNOPSIS
        Returns lab uptime and TTL status.

    .DESCRIPTION
        Queries lab VM status and TTL configuration to report current uptime,
        TTL remaining time, and overall status. Reads cached state from
        lab-ttl-state.json when available, falls back to live VM query.

    .PARAMETER StatePath
        Path to the TTL state JSON file. Defaults to .planning/lab-ttl-state.json.

    .OUTPUTS
        PSCustomObject with LabName, StartTime, ElapsedHours, TTLConfigured,
        TTLRemainingMinutes, Action, Status fields.
        Returns empty array @() when no lab VMs are running.

    .EXAMPLE
        Get-LabUptime
        Returns current lab uptime and TTL status.

    .EXAMPLE
        Get-LabUptime | Format-Table
        Displays lab uptime information in table format.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$StatePath
    )

    # Determine state path
    if (-not $StatePath) {
        $planningDir = Join-Path (Split-Path -Parent $PSScriptRoot) '.planning'
        $StatePath = Join-Path $planningDir 'lab-ttl-state.json'
    }

    # Check for running VMs
    $labVMs = @(Get-VM -ErrorAction SilentlyContinue)
    if ($labVMs.Count -eq 0) { return @() }

    $config = Get-LabTTLConfig
    $labName = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('Lab') -and $GlobalLabConfig.Lab.ContainsKey('Name')) {
            $GlobalLabConfig.Lab.Name
        } else { 'Lab' }
    } else { 'Lab' }

    # Try cached state first
    $startTime = Get-Date
    $ttlExpired = $false
    if (Test-Path $StatePath) {
        try {
            $raw = Get-Content -Path $StatePath -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $cached = $raw | ConvertFrom-Json
                if ($cached.StartTime) { $startTime = [datetime]$cached.StartTime }
                if ($null -ne $cached.TTLExpired) { $ttlExpired = [bool]$cached.TTLExpired }
            }
        }
        catch { <# fall through to defaults #> }
    }

    $elapsed = (Get-Date) - $startTime
    $elapsedHours = [math]::Round($elapsed.TotalHours, 1)

    $ttlConfigured = $config.Enabled
    $ttlRemainingMinutes = -1
    if ($ttlConfigured -and $config.WallClockHours -gt 0) {
        $ttlRemainingMinutes = [int](($config.WallClockHours * 60) - $elapsed.TotalMinutes)
        if ($ttlRemainingMinutes -lt 0) { $ttlRemainingMinutes = 0 }
    }

    $status = if (-not $ttlConfigured) { 'Disabled' }
              elseif ($ttlExpired) { 'Expired' }
              else { 'Active' }

    return [pscustomobject]@{
        LabName              = $labName
        StartTime            = $startTime
        ElapsedHours         = $elapsedHours
        TTLConfigured        = $ttlConfigured
        TTLRemainingMinutes  = $ttlRemainingMinutes
        Action               = $config.Action
        Status               = $status
    }
}
