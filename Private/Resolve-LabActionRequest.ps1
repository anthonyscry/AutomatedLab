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

    switch ($Action) {
        'setup' {
            $resolvedAction = 'deploy'
            $resolvedMode = 'full'
        }
        'one-button-setup' {
            $resolvedAction = 'deploy'
            $resolvedMode = 'full'
        }
        'one-button-reset' {
            $resolvedAction = 'teardown'
            $resolvedMode = 'full'
        }
        'blow-away' {
            $resolvedAction = 'teardown'
            $resolvedMode = 'full'
        }
    }

    return [pscustomobject]@{
        Action = $resolvedAction
        Mode = $resolvedMode
    }
}
