function New-LabAppArgumentList {
    [CmdletBinding()]
    param(
        [hashtable]$Options
    )

    $argumentList = New-Object System.Collections.Generic.List[string]
    $safeOptions = if ($null -eq $Options) { @{} } else { $Options }

    if ($safeOptions.ContainsKey('Action') -and $null -ne $safeOptions.Action) {
        $argumentList.Add('-Action') | Out-Null
        $argumentList.Add([string]$safeOptions.Action) | Out-Null
    }

    if ($safeOptions.ContainsKey('Mode') -and $null -ne $safeOptions.Mode) {
        $argumentList.Add('-Mode') | Out-Null
        $argumentList.Add([string]$safeOptions.Mode) | Out-Null
    }

    $switchOptionOrder = @('NonInteractive', 'Force', 'RemoveNetwork', 'DryRun')
    foreach ($name in $switchOptionOrder) {
        if ($safeOptions.ContainsKey($name) -and [bool]$safeOptions[$name]) {
            $argumentList.Add("-$name") | Out-Null
        }
    }

    if ($safeOptions.ContainsKey('ProfilePath') -and $null -ne $safeOptions.ProfilePath) {
        $argumentList.Add('-ProfilePath') | Out-Null
        $argumentList.Add([string]$safeOptions.ProfilePath) | Out-Null
    }

    if ($safeOptions.ContainsKey('DefaultsFile') -and $null -ne $safeOptions.DefaultsFile) {
        $argumentList.Add('-DefaultsFile') | Out-Null
        $argumentList.Add([string]$safeOptions.DefaultsFile) | Out-Null
    }

    if ($safeOptions.ContainsKey('CoreOnly') -and [bool]$safeOptions.CoreOnly) {
        $argumentList.Add('-CoreOnly') | Out-Null
    }

    return $argumentList.ToArray()
}
