function Test-LabVirtualSwitchSubnetConflict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SwitchName,

        [Parameter(Mandatory = $true)]
        [string]$AddressSpace,

        [switch]$AutoFix
    )

    function ConvertTo-IPv4UInt32 {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Address
        )

        $parsed = [System.Net.IPAddress]::Parse($Address)
        $bytes = $parsed.GetAddressBytes()
        if ($bytes.Length -ne 4) {
            throw "Only IPv4 addresses are supported: '$Address'"
        }

        return ([uint32]$bytes[0] -shl 24) -bor
            ([uint32]$bytes[1] -shl 16) -bor
            ([uint32]$bytes[2] -shl 8) -bor
            [uint32]$bytes[3]
    }

    function Get-CidrRange {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Cidr
        )

        $parts = $Cidr.Split('/')
        if ($parts.Count -ne 2) {
            throw "AddressSpace must be in CIDR format, for example '10.0.10.0/24'."
        }

        $networkText = $parts[0].Trim()
        $prefixText = $parts[1].Trim()

        $prefixLength = 0
        if (-not [int]::TryParse($prefixText, [ref]$prefixLength) -or $prefixLength -lt 0 -or $prefixLength -gt 32) {
            throw "AddressSpace prefix length must be between 0 and 32: '$Cidr'"
        }

        $networkValue = ConvertTo-IPv4UInt32 -Address $networkText
        $maskValue = if ($prefixLength -eq 0) {
            [uint32]0
        }
        else {
            [uint32]((([uint64]1 -shl $prefixLength) - 1) -shl (32 - $prefixLength))
        }

        $hostMask = [uint32](-bnot $maskValue)
        $networkStart = [uint32]($networkValue -band $maskValue)
        $broadcast = [uint32]($networkStart -bor $hostMask)

        return [pscustomobject]@{
            PrefixLength = $prefixLength
            NetworkStart = $networkStart
            Broadcast = $broadcast
        }
    }

    $cmd = Get-Command -Name 'Get-NetIPAddress' -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return [pscustomobject]@{
            SwitchName = $SwitchName
            AddressSpace = $AddressSpace
            HasConflict = $false
            AutoFixAttempted = $false
            AutoFixApplied = $false
            ConflictingAdapters = @()
            FixedAdapters = @()
            UnresolvedAdapters = @()
            Message = 'Get-NetIPAddress command is unavailable. Subnet conflict check skipped.'
        }
    }

    $targetAlias = "vEthernet ($SwitchName)"
    $targetRange = Get-CidrRange -Cidr $AddressSpace

    $ipRows = @(
        Get-NetIPAddress |
            Where-Object {
                $hasFamily = $_.PSObject.Properties.Name -contains 'AddressFamily'
                if ($hasFamily) {
                    [string]$_.AddressFamily -eq 'IPv4'
                }
                else {
                    $true
                }
            }
    )

    $conflicts = New-Object System.Collections.Generic.List[object]
    foreach ($row in $ipRows) {
        $alias = [string]$row.InterfaceAlias
        $ip = [string]$row.IPAddress

        if ([string]::IsNullOrWhiteSpace($alias) -or [string]::IsNullOrWhiteSpace($ip)) {
            continue
        }

        if (-not $alias.StartsWith('vEthernet (', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ([string]::Equals($alias, $targetAlias, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $switchMatch = [regex]::Match($alias, '^vEthernet \((?<name>.+)\)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $otherSwitchName = if ($switchMatch.Success) { $switchMatch.Groups['name'].Value } else { $alias }

        try {
            $ipValue = ConvertTo-IPv4UInt32 -Address $ip
        }
        catch {
            continue
        }

        $inRange = ($ipValue -ge $targetRange.NetworkStart) -and ($ipValue -le $targetRange.Broadcast)
        if (-not $inRange) {
            continue
        }

        [void]$conflicts.Add([pscustomobject]@{
                InterfaceAlias = $alias
                SwitchName = $otherSwitchName
                IPAddress = $ip
                PrefixLength = $row.PrefixLength
            })
    }

    $fixedAdapters = New-Object System.Collections.Generic.List[object]
    $unresolvedAdapters = New-Object System.Collections.Generic.List[object]
    $autoFixAttempted = $false

    if ($AutoFix -and $conflicts.Count -gt 0) {
        $autoFixAttempted = $true
        $removeCmd = Get-Command -Name 'Remove-NetIPAddress' -ErrorAction SilentlyContinue
        if ($null -eq $removeCmd) {
            foreach ($conflict in $conflicts) {
                [void]$unresolvedAdapters.Add([pscustomobject]@{
                        InterfaceAlias = $conflict.InterfaceAlias
                        SwitchName = $conflict.SwitchName
                        IPAddress = $conflict.IPAddress
                        PrefixLength = $conflict.PrefixLength
                        Error = 'Remove-NetIPAddress command is unavailable.'
                    })
            }
        }
        else {
            foreach ($conflict in $conflicts) {
                try {
                    Remove-NetIPAddress -InterfaceAlias $conflict.InterfaceAlias -IPAddress $conflict.IPAddress -Confirm:$false -ErrorAction Stop
                    [void]$fixedAdapters.Add($conflict)
                }
                catch {
                    [void]$unresolvedAdapters.Add([pscustomobject]@{
                            InterfaceAlias = $conflict.InterfaceAlias
                            SwitchName = $conflict.SwitchName
                            IPAddress = $conflict.IPAddress
                            PrefixLength = $conflict.PrefixLength
                            Error = $_.Exception.Message
                        })
                }
            }
        }
    }

    $hasConflict = if ($AutoFix) {
        $unresolvedAdapters.Count -gt 0
    }
    else {
        $conflicts.Count -gt 0
    }

    $autoFixApplied = $autoFixAttempted -and ($unresolvedAdapters.Count -eq 0)
    $message = if ($hasConflict) {
        "Detected $($conflicts.Count) conflicting vEthernet adapter(s) in subnet $AddressSpace."
    }
    elseif ($autoFixApplied) {
        "Detected and auto-fixed $($fixedAdapters.Count) conflicting vEthernet adapter(s) in subnet $AddressSpace."
    }
    else {
        "No conflicting vEthernet adapters detected in subnet $AddressSpace."
    }

    return [pscustomobject]@{
        SwitchName = $SwitchName
        AddressSpace = $AddressSpace
        HasConflict = $hasConflict
        AutoFixAttempted = $autoFixAttempted
        AutoFixApplied = $autoFixApplied
        ConflictingAdapters = $conflicts.ToArray()
        FixedAdapters = $fixedAdapters.ToArray()
        UnresolvedAdapters = $unresolvedAdapters.ToArray()
        Message = $message
    }
}

function Test-LabMultiSwitchSubnetOverlap {
    <#
    .SYNOPSIS
        Performs pairwise subnet overlap detection across multiple named switch definitions.

    .DESCRIPTION
        Takes an array of switch definitions and checks every pair for subnet overlap.
        Unlike Test-LabVirtualSwitchSubnetConflict (which checks a single switch against
        live host adapters), this function operates at the config level -- before any
        switches are created -- making it suitable for pre-deployment validation.

        Two subnets overlap when one contains or intersects the other. This includes:
        - Identical subnets
        - A smaller subnet wholly contained within a larger supernet

    .PARAMETER Switches
        Array of switch definitions. Each entry must have:
          - Name        : string, the switch name
          - AddressSpace: string, CIDR notation (e.g. "10.0.10.0/24")

    .OUTPUTS
        PSCustomObject with:
          HasOverlap (bool)
          Overlaps   (array of objects: Switch1, Switch2, Subnet1, Subnet2)
          Message    (string summary)

    .EXAMPLE
        $switches = @(
            [PSCustomObject]@{ Name = 'LabCorpNet'; AddressSpace = '10.0.10.0/24' }
            [PSCustomObject]@{ Name = 'LabDMZ';     AddressSpace = '10.0.20.0/24' }
        )
        Test-LabMultiSwitchSubnetOverlap -Switches $switches
        # HasOverlap = False
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Switches
    )

    # -- Inner helpers (reuse logic from Test-LabVirtualSwitchSubnetConflict) --

    function ConvertTo-IPv4UInt32Inner {
        param([string]$Address)
        $parsed = [System.Net.IPAddress]::Parse($Address)
        $bytes  = $parsed.GetAddressBytes()
        if ($bytes.Length -ne 4) {
            throw "Only IPv4 addresses are supported: '$Address'"
        }
        return ([uint32]$bytes[0] -shl 24) -bor `
               ([uint32]$bytes[1] -shl 16) -bor `
               ([uint32]$bytes[2] -shl 8)  -bor `
               [uint32]$bytes[3]
    }

    function Get-CidrRangeInner {
        param([string]$Cidr)
        $parts = $Cidr.Split('/')
        if ($parts.Count -ne 2) {
            throw "AddressSpace must be in CIDR format, e.g. '10.0.10.0/24'. Got: '$Cidr'"
        }
        $networkText  = $parts[0].Trim()
        $prefixText   = $parts[1].Trim()
        $prefixLength = 0
        if (-not [int]::TryParse($prefixText, [ref]$prefixLength) -or $prefixLength -lt 0 -or $prefixLength -gt 32) {
            throw "AddressSpace prefix length must be between 0 and 32: '$Cidr'"
        }
        $networkValue = ConvertTo-IPv4UInt32Inner -Address $networkText
        $maskValue    = if ($prefixLength -eq 0) {
            [uint32]0
        } else {
            [uint32]((([uint64]1 -shl $prefixLength) - 1) -shl (32 - $prefixLength))
        }
        $hostMask     = [uint32](-bnot $maskValue)
        $networkStart = [uint32]($networkValue -band $maskValue)
        $broadcast    = [uint32]($networkStart -bor $hostMask)
        return [PSCustomObject]@{
            PrefixLength = $prefixLength
            NetworkStart = $networkStart
            Broadcast    = $broadcast
        }
    }

    function Test-CidrOverlap {
        param([string]$CidrA, [string]$CidrB)
        $rangeA = Get-CidrRangeInner -Cidr $CidrA
        $rangeB = Get-CidrRangeInner -Cidr $CidrB
        # Two subnets overlap when their IP ranges intersect
        return ($rangeA.NetworkStart -le $rangeB.Broadcast) -and ($rangeB.NetworkStart -le $rangeA.Broadcast)
    }

    # -- Pairwise check -------------------------------------------------------

    $overlaps = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $Switches.Count; $i++) {
        for ($j = $i + 1; $j -lt $Switches.Count; $j++) {
            $swA = $Switches[$i]
            $swB = $Switches[$j]

            $nameA  = if ($swA -is [hashtable]) { $swA['Name'] }         else { $swA.Name }
            $nameB  = if ($swB -is [hashtable]) { $swB['Name'] }         else { $swB.Name }
            $addrA  = if ($swA -is [hashtable]) { $swA['AddressSpace'] } else { $swA.AddressSpace }
            $addrB  = if ($swB -is [hashtable]) { $swB['AddressSpace'] } else { $swB.AddressSpace }

            try {
                if (Test-CidrOverlap -CidrA $addrA -CidrB $addrB) {
                    [void]$overlaps.Add([PSCustomObject]@{
                        Switch1 = $nameA
                        Switch2 = $nameB
                        Subnet1 = $addrA
                        Subnet2 = $addrB
                    })
                }
            }
            catch {
                Write-Warning "Test-LabMultiSwitchSubnetOverlap: could not compare '$nameA' ($addrA) with '$nameB' ($addrB) - $_"
            }
        }
    }

    $hasOverlap = $overlaps.Count -gt 0
    $message    = if ($hasOverlap) {
        "Detected $($overlaps.Count) subnet overlap(s) across configured switches."
    } else {
        "No subnet overlaps detected across $($Switches.Count) configured switch(es)."
    }

    return [PSCustomObject]@{
        HasOverlap = $hasOverlap
        Overlaps   = $overlaps.ToArray()
        Message    = $message
    }
}
