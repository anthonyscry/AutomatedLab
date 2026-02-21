Set-StrictMode -Version Latest

function Get-LabCustomRole {
    <#
    .SYNOPSIS
        Loads and discovers custom lab roles from JSON files in .planning/roles/.
    .DESCRIPTION
        Auto-discovers all *.json role files in the roles directory (defaulting to
        <repo-root>/.planning/roles/), validates each against the custom role schema,
        and returns role metadata (for -List) or a full role hashtable (for -Name).
    .PARAMETER Name
        Return a single role matching this name or tag (case-insensitive).
    .PARAMETER List
        Return a list of all discovered valid custom roles with summary metadata.
    .PARAMETER RolesPath
        Override the default roles directory path.
    .PARAMETER Config
        Optional lab configuration hashtable used to populate VM-level settings
        (VMNames, IPPlan, Network, etc.) when returning a single role by -Name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [switch]$List,

        [Parameter(Mandatory = $false)]
        [string]$RolesPath,

        [Parameter(Mandatory = $false)]
        [hashtable]$Config
    )

    # -- Path resolution ------------------------------------------------------
    if (-not $PSBoundParameters.ContainsKey('RolesPath') -or [string]::IsNullOrWhiteSpace($RolesPath)) {
        # PS 5.1 compatible: nested Join-Path (no 3-arg form)
        $RolesPath = Join-Path (Join-Path $PSScriptRoot '..') '.planning'
        $RolesPath = Join-Path $RolesPath 'roles'
    }

    # Normalise to absolute path
    $RolesPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RolesPath)

    if (-not (Test-Path -LiteralPath $RolesPath -PathType Container)) {
        Write-Verbose "Get-LabCustomRole: roles directory not found at '$RolesPath'. No custom roles available."
        if ($List) { return @() }
        return $null
    }

    # -- Ensure schema validator is available ---------------------------------
    if (-not (Get-Command 'Test-LabCustomRoleSchema' -ErrorAction SilentlyContinue)) {
        $validatorPath = Join-Path $PSScriptRoot 'Test-LabCustomRoleSchema.ps1'
        if (Test-Path -LiteralPath $validatorPath) {
            . $validatorPath
        }
        else {
            throw "Get-LabCustomRole: cannot find Test-LabCustomRoleSchema.ps1 at '$validatorPath'"
        }
    }

    # -- Discover JSON files ---------------------------------------------------
    $jsonFiles = @(Get-ChildItem -Path $RolesPath -Filter '*.json' -File -ErrorAction SilentlyContinue)
    $validRoles = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($file in $jsonFiles) {
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop

            # Convert top-level PSCustomObject to hashtable
            $roleHt = Convert-PsObjectToHashtable -InputObject $parsed

            # Convert provisioningSteps items to hashtables
            if ($roleHt.ContainsKey('provisioningSteps') -and $null -ne $roleHt['provisioningSteps']) {
                $convertedSteps = @()
                foreach ($step in @($roleHt['provisioningSteps'])) {
                    if ($step -is [System.Management.Automation.PSCustomObject]) {
                        $convertedSteps += Convert-PsObjectToHashtable -InputObject $step
                    }
                    else {
                        $convertedSteps += $step
                    }
                }
                $roleHt['provisioningSteps'] = $convertedSteps
            }

            # Convert resources to hashtable if present
            if ($roleHt.ContainsKey('resources') -and $roleHt['resources'] -is [System.Management.Automation.PSCustomObject]) {
                $roleHt['resources'] = Convert-PsObjectToHashtable -InputObject $roleHt['resources']
            }

            # Validate schema
            $validation = Test-LabCustomRoleSchema -RoleData $roleHt -FilePath $file.FullName
            if (-not $validation.Valid) {
                $errList = $validation.Errors -join '; '
                Write-Warning "Get-LabCustomRole: skipping '$($file.FullName)' -- validation errors: $errList"
                continue
            }

            # Attach source file path to the hashtable
            $roleHt['_filePath'] = $file.FullName
            $validRoles.Add($roleHt)
        }
        catch {
            Write-Warning "Get-LabCustomRole: failed to parse '$($file.FullName)' -- $($_.Exception.Message)"
        }
    }

    # -- -List mode ------------------------------------------------------------
    if ($List) {
        $listResult = foreach ($role in $validRoles) {
            $stepCount = 0
            if ($role.ContainsKey('provisioningSteps') -and $null -ne $role['provisioningSteps']) {
                $stepCount = @($role['provisioningSteps']).Count
            }

            $resources = $null
            if ($role.ContainsKey('resources') -and $null -ne $role['resources']) {
                $resources = $role['resources']
            }

            [pscustomobject]@{
                Name                 = $role['name']
                Tag                  = $role['tag']
                Description          = $role['description']
                OS                   = $role['os']
                Resources            = $resources
                FilePath             = $role['_filePath']
                ProvisioningStepCount = $stepCount
            }
        }

        return @($listResult | Sort-Object -Property Name)
    }

    # -- -Name mode ------------------------------------------------------------
    if ($PSBoundParameters.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace($Name)) {
        $match = $null
        foreach ($role in $validRoles) {
            if ($role['name'] -ieq $Name -or $role['tag'] -ieq $Name) {
                $match = $role
                break
            }
        }

        if ($null -eq $match) {
            Write-Verbose "Get-LabCustomRole: no custom role found with name or tag '$Name'"
            return $null
        }

        # Build output hashtable in Get-LabRole_* compatible shape
        $tag = $match['tag']
        $vmName = if ($match.ContainsKey('vmNameDefault')) { $match['vmNameDefault'] } else { $tag }

        if ($null -ne $Config) {
            if ($Config.ContainsKey('VMNames') -and $Config.VMNames -is [hashtable] -and $Config.VMNames.ContainsKey($tag)) {
                $vmName = $Config.VMNames[$tag]
            }
        }

        $ip = ''
        $gateway = ''
        $dnsServer1 = ''
        $domainName = ''
        $network = ''
        $osValue = ''

        if ($null -ne $Config) {
            if ($Config.ContainsKey('IPPlan') -and $Config.IPPlan -is [hashtable] -and $Config.IPPlan.ContainsKey($tag)) {
                $ip = $Config.IPPlan[$tag]
            }
            if ($Config.ContainsKey('Network') -and $Config.Network -is [hashtable]) {
                if ($Config.Network.ContainsKey('Gateway')) { $gateway = $Config.Network.Gateway }
                if ($Config.Network.ContainsKey('SwitchName')) { $network = $Config.Network.SwitchName }
            }
            if ($Config.ContainsKey('IPPlan') -and $Config.IPPlan -is [hashtable] -and $Config.IPPlan.ContainsKey('DC')) {
                $dnsServer1 = $Config.IPPlan.DC
            }
            if ($Config.ContainsKey('DomainName')) { $domainName = $Config.DomainName }

            # Resolve OS from config based on role.os
            $roleOS = $match['os']
            if ($roleOS -ieq 'windows') {
                if ($Config.ContainsKey('ServerOS')) { $osValue = $Config.ServerOS }
            }
            elseif ($roleOS -ieq 'linux') {
                if ($Config.ContainsKey('LinuxOS')) { $osValue = $Config.LinuxOS }
            }
        }

        # Parse memory values from resources
        $resources = if ($match.ContainsKey('resources')) { $match['resources'] } else { @{} }
        $memStr    = if ($resources.ContainsKey('memory'))    { $resources['memory'] }    else { '2GB' }
        $minStr    = if ($resources.ContainsKey('minMemory')) { $resources['minMemory'] } else { '1GB' }
        $maxStr    = if ($resources.ContainsKey('maxMemory')) { $resources['maxMemory'] } else { '4GB' }
        $memory    = ConvertTo-LabMemoryValue -MemoryString $memStr
        $minMemory = ConvertTo-LabMemoryValue -MemoryString $minStr
        $maxMemory = ConvertTo-LabMemoryValue -MemoryString $maxStr
        $processors = if ($resources.ContainsKey('processors')) { [int]$resources['processors'] } else { 2 }

        $autoLabRoles = @()
        if ($match.ContainsKey('autoLabRoles') -and $null -ne $match['autoLabRoles']) {
            $autoLabRoles = @($match['autoLabRoles'])
        }

        return @{
            Tag               = $tag
            VMName            = $vmName
            Roles             = $autoLabRoles
            OS                = $osValue
            IP                = $ip
            Gateway           = $gateway
            DnsServer1        = $dnsServer1
            Memory            = $memory
            MinMemory         = $minMemory
            MaxMemory         = $maxMemory
            Processors        = $processors
            DomainName        = $domainName
            Network           = $network
            IsCustomRole      = $true
            ProvisioningSteps = $match['provisioningSteps']
            SourceFile        = $match['_filePath']
        }
    }

    # Neither -List nor -Name specified
    Write-Warning "Get-LabCustomRole: specify -List to enumerate roles or -Name <roleName> to retrieve a specific role."
    return $null
}

# -- Private helpers -----------------------------------------------------------

function Convert-PsObjectToHashtable {
    <#
    .SYNOPSIS
        Converts a PSCustomObject to a hashtable (shallow, top level only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $ht[$prop.Name] = $prop.Value
    }
    return $ht
}

function ConvertTo-LabMemoryValue {
    <#
    .SYNOPSIS
        Converts a memory string like '4GB' or '512MB' to a numeric byte value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MemoryString
    )

    if ($MemoryString -match '^(\d+)(GB|MB)$') {
        $amount = [long]$Matches[1]
        $unit   = $Matches[2]
        switch ($unit) {
            'GB' { return $amount * 1GB }
            'MB' { return $amount * 1MB }
        }
    }

    # Fallback: try parsing as plain number (assume bytes)
    $parsed = $null
    if ([long]::TryParse($MemoryString, [ref]$parsed)) {
        return $parsed
    }

    Write-Warning "ConvertTo-LabMemoryValue: cannot parse memory value '$MemoryString'. Defaulting to 2GB."
    return 2GB
}
