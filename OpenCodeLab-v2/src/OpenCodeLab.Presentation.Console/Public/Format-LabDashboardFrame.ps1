Set-StrictMode -Version Latest

function Format-LabDashboardFrame {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Status,

        [Parameter()]
        [object[]]$Events,

        [Parameter()]
        [object[]]$Diagnostics
    )

    if ($null -eq $Status) {
        $Status = @{}
    }

    if ($null -eq $Events) {
        $Events = @()
    }

    if ($null -eq $Diagnostics) {
        $Diagnostics = @()
    }

    $lockState = if ($Status.ContainsKey('Lock') -and -not [string]::IsNullOrWhiteSpace([string]$Status.Lock)) { [string]$Status.Lock } else { 'unknown' }
    $profile = if ($Status.ContainsKey('Profile') -and -not [string]::IsNullOrWhiteSpace([string]$Status.Profile)) { [string]$Status.Profile } else { 'unknown' }

    return @"
LOCK: $lockState
PROFILE: $profile

CORE STATUS
EVENT STREAM ($($Events.Count))
DIAGNOSTICS ($($Diagnostics.Count))
"@
}
