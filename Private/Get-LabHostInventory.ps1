function Get-LabHostInventory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InventoryPath,

        [Parameter()]
        [string[]]$TargetHosts = @()
    )

    $requestedTargets = @($TargetHosts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $hasTargetFilter = $requestedTargets.Count -gt 0
    $targetLookup = $null
    if ($hasTargetFilter) {
        $targetLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($target in $requestedTargets) {
            [void]$targetLookup.Add($target.Trim())
        }
    }

    if ([string]::IsNullOrWhiteSpace($InventoryPath)) {
        $localName = [Environment]::MachineName
        $hosts = @(
            [pscustomobject]@{
                Name = $localName
                Role = 'primary'
                Connection = 'local'
            }
        )

        if ($hasTargetFilter) {
            $hosts = @($hosts | Where-Object { $targetLookup.Contains($_.Name) })
        }

        return [pscustomobject]@{
            Source = 'default-local'
            Hosts = $hosts
        }
    }

    $inventoryItem = $null
    try {
        $inventoryItem = Get-Item -LiteralPath $InventoryPath -ErrorAction Stop
    }
    catch {
        throw "Failed to read inventory file '$InventoryPath': $($_.Exception.Message)"
    }

    if ($inventoryItem.PSProvider.Name -ne 'FileSystem') {
        throw "InventoryPath must resolve to a filesystem file. Path '$InventoryPath' resolves to provider '$($inventoryItem.PSProvider.Name)'."
    }

    if ($inventoryItem.PSIsContainer) {
        throw "InventoryPath must resolve to a filesystem file. Path '$InventoryPath' is a directory."
    }

    $resolvedPath = $inventoryItem.FullName

    try {
        $rawInventory = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop
    }
    catch {
        throw "Failed to read inventory file '$InventoryPath': $($_.Exception.Message)"
    }

    try {
        $parsedInventory = $rawInventory | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid inventory JSON in '$InventoryPath': $($_.Exception.Message)"
    }

    $inventoryProperties = @($parsedInventory.PSObject.Properties.Name)
    if ($inventoryProperties -notcontains 'hosts') {
        throw "Invalid inventory JSON in '$InventoryPath': required property 'hosts' is missing."
    }

    $normalizedHosts = New-Object System.Collections.Generic.List[object]
    $rawHosts = @($parsedInventory.hosts)

    if ($rawHosts.Count -eq 0) {
        throw "Invalid inventory JSON in '$InventoryPath': hosts array is empty."
    }

    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    for ($index = 0; $index -lt $rawHosts.Count; $index++) {
        $hostEntry = $rawHosts[$index]
        $name = [string]$hostEntry.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Invalid inventory JSON in '$InventoryPath': hosts[$index].name is required."
        }

        $trimmedName = $name.Trim()
        if (-not $seenNames.Add($trimmedName)) {
            throw "Invalid inventory JSON in '$InventoryPath': duplicate host name '$trimmedName' at hosts[$index]."
        }

        # Validate and default connection field
        $allowedConnections = @('local', 'winrm', 'ssh', 'psremoting')
        $rawConnection = ([string]$hostEntry.connection).Trim()
        if ([string]::IsNullOrWhiteSpace($rawConnection)) {
            $rawConnection = 'local'
        }
        $connectionLower = $rawConnection.ToLowerInvariant()
        if ($allowedConnections -notcontains $connectionLower) {
            throw "Invalid inventory JSON in '$InventoryPath': hosts[$index].connection value '$rawConnection' is not supported. Allowed: $($allowedConnections -join ', ')."
        }

        # Default role when empty
        $rawRole = ([string]$hostEntry.role).Trim()
        if ([string]::IsNullOrWhiteSpace($rawRole)) {
            $rawRole = if ($index -eq 0) { 'primary' } else { 'secondary' }
        }

        $hostObject = [pscustomobject]@{
            Name = $trimmedName
            Role = $rawRole
            Connection = $connectionLower
        }

        if (($null -eq $targetLookup) -or $targetLookup.Contains($hostObject.Name)) {
            [void]$normalizedHosts.Add($hostObject)
        }
    }

    return [pscustomobject]@{
        Source = $resolvedPath
        Hosts = $normalizedHosts.ToArray()
    }
}
