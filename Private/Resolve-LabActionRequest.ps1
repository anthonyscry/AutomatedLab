function Resolve-LabActionRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [ValidateSet('quick', 'full')]
        [string]$Mode = 'full'
    )

    $resolvedAction = $Action
    $resolvedMode = $Mode

    $aliasMap = @{
        'setup' = @{ Action = 'deploy'; Mode = 'full' }
        'one-button-setup' = @{ Action = 'deploy'; Mode = 'full' }
        'one-button-reset' = @{ Action = 'teardown'; Mode = 'full' }
        'blow-away' = @{ Action = 'teardown'; Mode = 'full' }
    }

    if ($aliasMap.ContainsKey($Action)) {
        $resolvedAction = $aliasMap[$Action].Action
        $resolvedMode = $aliasMap[$Action].Mode
    }

    return [pscustomobject]@{
        Action = $resolvedAction
        Mode = $resolvedMode
    }
}
