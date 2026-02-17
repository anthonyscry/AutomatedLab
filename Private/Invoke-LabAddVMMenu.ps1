function Invoke-LabAddVMMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$LabConfig,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    Write-Host ''
    Write-Host '  ADD VM' -ForegroundColor Cyan
    Write-Host '   [1] Add additional Server VM' -ForegroundColor White
    Write-Host '   [2] Add additional Workstation VM' -ForegroundColor White
    Write-Host '   [X] Back' -ForegroundColor DarkGray

    $vmChoice = (Read-Host '  Select').Trim().ToUpperInvariant()
    switch ($vmChoice) {
        '1' { Invoke-LabAddVMWizard -VMType 'Server' -LabConfig $LabConfig -RunEvents $RunEvents }
        '2' { Invoke-LabAddVMWizard -VMType 'Workstation' -LabConfig $LabConfig -RunEvents $RunEvents }
        'X' { return }
        default { Write-Host '  Invalid selection.' -ForegroundColor Red }
    }
}
