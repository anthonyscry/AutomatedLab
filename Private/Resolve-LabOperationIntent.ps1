function Resolve-LabOperationIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter()]
        [string]$Mode = 'full',

        [Parameter()]
        [string[]]$TargetHosts = @(),

        [Parameter()]
        [string]$InventoryPath
    )

    $normalizedAction = $Action.Trim().ToLowerInvariant()
    $normalizedMode = $Mode.Trim().ToLowerInvariant()

    if ($normalizedAction -notin @('deploy', 'teardown')) {
        throw "Unsupported action '$Action'. Supported actions are: deploy, teardown."
    }

    if ($normalizedMode -notin @('quick', 'full')) {
        throw "Unsupported mode '$Mode'. Supported modes are: quick, full."
    }

    $inventory = Get-LabHostInventory -InventoryPath $InventoryPath -TargetHosts $TargetHosts

    return [pscustomobject]@{
        Action = $normalizedAction
        RequestedMode = $normalizedMode
        TargetHosts = @($inventory.Hosts | ForEach-Object { $_.Name })
        InventorySource = $inventory.Source
        RequestorMachine = [Environment]::MachineName
        RequestorUser = [Environment]::UserName
    }
}
