function Get-LabPerformanceConfig {
    <#
    .SYNOPSIS
        Reads performance configuration from GlobalLabConfig with safe defaults.

    .DESCRIPTION
        Returns a PSCustomObject with Performance settings. Uses ContainsKey guards on
        every read to prevent StrictMode failures when keys are absent.
        Returns safe defaults when the Performance block or individual keys are missing.

    .OUTPUTS
        PSCustomObject with Enabled, StoragePath, RetentionDays fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $performanceBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('Performance')) { $GlobalLabConfig.Performance } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        Enabled       = if ($performanceBlock.ContainsKey('Enabled'))       { [bool]$performanceBlock.Enabled }       else { $true }
        StoragePath   = if ($performanceBlock.ContainsKey('StoragePath'))   { [string]$performanceBlock.StoragePath } else { '.planning/performance-metrics.json' }
        RetentionDays = if ($performanceBlock.ContainsKey('RetentionDays')) { [int]$performanceBlock.RetentionDays }   else { 90 }
    }
}
