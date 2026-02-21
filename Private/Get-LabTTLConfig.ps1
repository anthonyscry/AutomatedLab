function Get-LabTTLConfig {
    <#
    .SYNOPSIS
        Reads TTL configuration from GlobalLabConfig with safe defaults.

    .DESCRIPTION
        Returns a PSCustomObject with TTL settings. Uses ContainsKey guards on
        every read to prevent StrictMode failures when keys are absent.
        Returns safe defaults when the TTL block or individual keys are missing.

    .OUTPUTS
        PSCustomObject with Enabled, IdleMinutes, WallClockHours, Action fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $ttlBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('TTL')) { $GlobalLabConfig.TTL } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        Enabled        = if ($ttlBlock.ContainsKey('Enabled'))        { [bool]$ttlBlock.Enabled }        else { $false }
        IdleMinutes    = if ($ttlBlock.ContainsKey('IdleMinutes'))    { [int]$ttlBlock.IdleMinutes }      else { 0 }
        WallClockHours = if ($ttlBlock.ContainsKey('WallClockHours')) { [int]$ttlBlock.WallClockHours }   else { 8 }
        Action         = if ($ttlBlock.ContainsKey('Action'))         { [string]$ttlBlock.Action }        else { 'Suspend' }
    }
}
