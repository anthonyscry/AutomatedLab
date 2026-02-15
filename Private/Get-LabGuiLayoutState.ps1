function Get-LabGuiLayoutState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$Mode,

        [string]$ProfilePath,

        [string[]]$TargetHosts
    )

    $guard = Get-LabGuiDestructiveGuard -Action $Action -Mode $Mode -ProfilePath $ProfilePath

    $normalizedTargets = @(
        @($TargetHosts) |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_ -split '[,;\s]+' } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )

    return [pscustomobject]@{
        ShowAdvanced = $guard.RequiresConfirmation -or ($normalizedTargets.Count -gt 0)
        AdvancedForDestructiveAction = [bool]$guard.RequiresConfirmation
        HasTargetHosts = ($normalizedTargets.Count -gt 0)
        RecommendedNonInteractiveDefault = [bool]$guard.RecommendedNonInteractiveDefault
    }
}
