function Get-LabADMXConfig {
    <#
    .SYNOPSIS
        Reads ADMX configuration from GlobalLabConfig with safe defaults.

    .DESCRIPTION
        Returns a PSCustomObject with ADMX settings. Uses ContainsKey guards on
        every read to prevent StrictMode failures when keys are absent.
        Returns safe defaults when the ADMX block or individual keys are missing.

    .OUTPUTS
        PSCustomObject with Enabled, CreateBaselineGPO, ThirdPartyADMX fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $admxBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('ADMX')) { $GlobalLabConfig.ADMX } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        Enabled            = if ($admxBlock.ContainsKey('Enabled'))            { [bool]$admxBlock.Enabled }             else { $true }
        CreateBaselineGPO  = if ($admxBlock.ContainsKey('CreateBaselineGPO')) { [bool]$admxBlock.CreateBaselineGPO }  else { $false }
        ThirdPartyADMX     = if ($admxBlock.ContainsKey('ThirdPartyADMX'))     { $admxBlock.ThirdPartyADMX }            else { @() }
    }
}
