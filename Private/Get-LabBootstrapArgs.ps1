function Get-LabBootstrapArgs {
    [CmdletBinding()]
    param(
        [ValidateSet('quick', 'full')][string]$Mode = 'full',
        [switch]$NonInteractive,
        [switch]$AutoFixSubnetConflict
    )

    $scriptArgs = @()
    $scriptArgs += @('-Mode', $Mode)
    if ($NonInteractive) { $scriptArgs += '-NonInteractive' }
    if ($AutoFixSubnetConflict) { $scriptArgs += '-AutoFixSubnetConflict' }
    return $scriptArgs
}
