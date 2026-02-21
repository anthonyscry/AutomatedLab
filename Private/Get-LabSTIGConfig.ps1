function Get-LabSTIGConfig {
    <#
    .SYNOPSIS
        Reads STIG configuration from GlobalLabConfig with safe defaults.

    .DESCRIPTION
        Returns a PSCustomObject with STIG settings. Uses ContainsKey guards on
        every read to prevent StrictMode failures when keys are absent.
        Returns safe defaults when the STIG block or individual keys are missing.

    .OUTPUTS
        PSCustomObject with Enabled, AutoApplyOnDeploy, ComplianceCachePath, Exceptions fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $stigBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('STIG')) { $GlobalLabConfig.STIG } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        Enabled             = if ($stigBlock.ContainsKey('Enabled'))             { [bool]$stigBlock.Enabled }              else { $false }
        AutoApplyOnDeploy   = if ($stigBlock.ContainsKey('AutoApplyOnDeploy'))   { [bool]$stigBlock.AutoApplyOnDeploy }    else { $true }
        ComplianceCachePath = if ($stigBlock.ContainsKey('ComplianceCachePath')) { [string]$stigBlock.ComplianceCachePath } else { '.planning/stig-compliance.json' }
        Exceptions          = if ($stigBlock.ContainsKey('Exceptions'))          { $stigBlock.Exceptions }                 else { @{} }
    }
}
