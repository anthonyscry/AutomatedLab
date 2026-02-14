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

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InventoryPath)

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
    for ($index = 0; $index -lt $rawHosts.Count; $index++) {
        $hostEntry = $rawHosts[$index]
        $name = [string]$hostEntry.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Invalid inventory JSON in '$InventoryPath': hosts[$index].name is required."
        }

        $hostObject = [pscustomobject]@{
            Name = $name.Trim()
            Role = ([string]$hostEntry.role).Trim()
            Connection = ([string]$hostEntry.connection).Trim()
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
