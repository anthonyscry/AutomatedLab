function Resolve-LabActionRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [ValidateSet('quick', 'full')]
        [string]$Mode = 'full'
    )

    try {
        $resolvedAction = $Action
        $resolvedMode = $Mode

        if ($Action -in @('setup', 'one-button-setup', 'one-button-reset', 'blow-away')) {
            $resolvedMode = 'full'
        }

        return [pscustomobject]@{
            Action = $resolvedAction
            Mode = $resolvedMode
        }
    }
    catch {
        throw "Resolve-LabActionRequest: failed to resolve action request - $_"
    }
}
