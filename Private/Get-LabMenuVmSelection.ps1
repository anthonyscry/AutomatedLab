function Get-LabMenuVmSelection {
    [CmdletBinding()]
    param(
        [string]$SuggestedVM = '',
        [string[]]$CoreVMNames
    )

    $vmNames = @()
    try {
        $vmNames = @(Hyper-V\Get-VM -ErrorAction Stop | Select-Object -ExpandProperty Name)
    } catch {
        $vmNames = @(@($CoreVMNames)) + @('LIN1')
    }

    $vmNames = @($vmNames | Sort-Object -Unique)
    if (-not $vmNames -or $vmNames.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($SuggestedVM)) {
            return $SuggestedVM
        }
        return (Read-Host '  Target VM name').Trim()
    }

    Write-Host ''
    Write-Host '  Available target VMs:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $vmNames.Count; $i++) {
        Write-Host ("   [{0}] {1}" -f ($i + 1), $vmNames[$i]) -ForegroundColor Gray
    }
    Write-Host '   [N] Enter custom VM name' -ForegroundColor Gray

    if (-not [string]::IsNullOrWhiteSpace($SuggestedVM)) {
        Write-Host ("  Suggested target: {0}" -f $SuggestedVM) -ForegroundColor DarkGray
    }

    $selection = (Read-Host '  Select target VM').Trim().ToUpperInvariant()
    if ($selection -eq 'N') {
        return (Read-Host '  Enter custom VM name').Trim()
    }

    $index = 0
    if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $vmNames.Count) {
        return $vmNames[$index - 1]
    }

    if (-not [string]::IsNullOrWhiteSpace($SuggestedVM)) {
        return $SuggestedVM
    }

    return $vmNames[0]
}
