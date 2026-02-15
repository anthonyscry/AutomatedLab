function New-LabAppArgumentList {
    [CmdletBinding()]
    param(
        [hashtable]$Options
    )

    $argumentList = New-Object System.Collections.Generic.List[string]
    $safeOptions = if ($null -eq $Options) { @{} } else { $Options }

    function ConvertTo-SafeBoolean {
        param($Value)

        if ($null -eq $Value) { return $false }
        if ($Value -is [bool]) { return $Value }

        if ($Value -is [string]) {
            $normalized = $Value.Trim().ToLowerInvariant()
            switch ($normalized) {
                { $_ -in @('true', '1', 'yes', 'on') } { return $true }
                { $_ -in @('false', '0', 'no', 'off', '') } { return $false }
                default { return $false }
            }
        }

        if ($Value -is [byte] -or
            $Value -is [sbyte] -or
            $Value -is [int16] -or
            $Value -is [uint16] -or
            $Value -is [int32] -or
            $Value -is [uint32] -or
            $Value -is [int64] -or
            $Value -is [uint64] -or
            $Value -is [decimal] -or
            $Value -is [single] -or
            $Value -is [double]) {
            return [double]$Value -ne 0
        }

        return $false
    }

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
        if ($safeOptions.ContainsKey($name) -and (ConvertTo-SafeBoolean -Value $safeOptions[$name])) {
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

    if ($safeOptions.ContainsKey('TargetHosts') -and $null -ne $safeOptions.TargetHosts) {
        $targetHosts = @($safeOptions.TargetHosts | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($targetHosts.Count -gt 0) {
            $argumentList.Add('-TargetHosts') | Out-Null
            foreach ($targetHost in $targetHosts) {
                $argumentList.Add($targetHost.Trim()) | Out-Null
            }
        }
    }

    if ($safeOptions.ContainsKey('ConfirmationToken') -and $null -ne $safeOptions.ConfirmationToken) {
        $confirmationToken = [string]$safeOptions.ConfirmationToken
        if (-not [string]::IsNullOrWhiteSpace($confirmationToken)) {
            $argumentList.Add('-ConfirmationToken') | Out-Null
            $argumentList.Add($confirmationToken.Trim()) | Out-Null
        }
    }

    if ($safeOptions.ContainsKey('CoreOnly') -and (ConvertTo-SafeBoolean -Value $safeOptions.CoreOnly)) {
        $argumentList.Add('-CoreOnly') | Out-Null
    }

    return $argumentList.ToArray()
}
