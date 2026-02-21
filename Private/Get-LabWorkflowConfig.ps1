function Get-LabWorkflowConfig {
    <#
    .SYNOPSIS
        Reads workflow configuration from global lab config.

    .DESCRIPTION
        Get-LabWorkflowConfig returns a Workflows configuration object with safe
        defaults when keys are missing from $GlobalLabConfig. Contains ContainsKey
        guards for all nested keys to prevent errors under StrictMode.

    .OUTPUTS
        [pscustomobject] with StoragePath, Enabled properties.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $config = $GlobalLabConfig

    $storagePath = if ($config.ContainsKey('Workflows') -and $config.Workflows.ContainsKey('StoragePath')) {
        [string]$config.Workflows.StoragePath
    } else {
        '.planning/workflows'
    }

    $enabled = if ($config.ContainsKey('Workflows') -and $config.Workflows.ContainsKey('Enabled')) {
        [bool]$config.Workflows.Enabled
    } else {
        $true
    }

    return [pscustomobject]@{
        StoragePath = $storagePath
        Enabled     = $enabled
    }
}
