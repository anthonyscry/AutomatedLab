function Get-LabAnalyticsConfig {
    <#
    .SYNOPSIS
        Reads analytics configuration from GlobalLabConfig with safe defaults.

    .DESCRIPTION
        Returns a PSCustomObject with Analytics settings. Uses ContainsKey guards on
        every read to prevent StrictMode failures when keys are absent.
        Returns safe defaults when the Analytics block or individual keys are missing.

    .OUTPUTS
        PSCustomObject with Enabled, StoragePath, RetentionDays fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $analyticsBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('Analytics')) { $GlobalLabConfig.Analytics } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        Enabled       = if ($analyticsBlock.ContainsKey('Enabled'))       { [bool]$analyticsBlock.Enabled }       else { $true }
        StoragePath   = if ($analyticsBlock.ContainsKey('StoragePath'))   { [string]$analyticsBlock.StoragePath } else { '.planning/analytics.json' }
        RetentionDays = if ($analyticsBlock.ContainsKey('RetentionDays')) { [int]$analyticsBlock.RetentionDays }   else { 90 }
    }
}
