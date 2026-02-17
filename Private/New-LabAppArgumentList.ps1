function New-LabAppArgumentList {
    [CmdletBinding()]
    param(
        [hashtable]$Options
    )

    try {
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
            [void]$argumentList.Add('-Action')
            [void]$argumentList.Add([string]$safeOptions.Action)
        }

        if ($safeOptions.ContainsKey('Mode') -and $null -ne $safeOptions.Mode) {
            [void]$argumentList.Add('-Mode')
            [void]$argumentList.Add([string]$safeOptions.Mode)
        }

        $switchOptionOrder = @('NonInteractive', 'Force', 'RemoveNetwork', 'DryRun')
        foreach ($name in $switchOptionOrder) {
            if ($safeOptions.ContainsKey($name) -and (ConvertTo-SafeBoolean -Value $safeOptions[$name])) {
                [void]$argumentList.Add("-$name")
            }
        }

        if ($safeOptions.ContainsKey('ProfilePath') -and $null -ne $safeOptions.ProfilePath) {
            [void]$argumentList.Add('-ProfilePath')
            [void]$argumentList.Add([string]$safeOptions.ProfilePath)
        }

        if ($safeOptions.ContainsKey('DefaultsFile') -and $null -ne $safeOptions.DefaultsFile) {
            [void]$argumentList.Add('-DefaultsFile')
            [void]$argumentList.Add([string]$safeOptions.DefaultsFile)
        }

        if ($safeOptions.ContainsKey('TargetHosts') -and $null -ne $safeOptions.TargetHosts) {
            $targetHosts = @($safeOptions.TargetHosts | ConvertTo-LabTargetHostList)
            if ($targetHosts.Count -gt 0) {
                [void]$argumentList.Add('-TargetHosts')
                foreach ($targetHost in $targetHosts) {
                    [void]$argumentList.Add($targetHost)
                }
            }
        }

        if ($safeOptions.ContainsKey('ConfirmationToken') -and $null -ne $safeOptions.ConfirmationToken) {
            $confirmationToken = [string]$safeOptions.ConfirmationToken
            if (-not [string]::IsNullOrWhiteSpace($confirmationToken)) {
                [void]$argumentList.Add('-ConfirmationToken')
                [void]$argumentList.Add($confirmationToken.Trim())
            }
        }

        if ($safeOptions.ContainsKey('CoreOnly') -and (ConvertTo-SafeBoolean -Value $safeOptions.CoreOnly)) {
            [void]$argumentList.Add('-CoreOnly')
        }

        return $argumentList.ToArray()
    }
    catch {
        throw "New-LabAppArgumentList: failed to build argument list - $_"
    }
}
