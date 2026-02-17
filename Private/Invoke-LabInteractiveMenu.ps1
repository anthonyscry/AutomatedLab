function Invoke-LabInteractiveMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$LabConfig,
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][string]$LabName,
        [Parameter(Mandatory)][ValidateSet('quick', 'full')][string]$EffectiveMode,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents,
        [switch]$NonInteractive,
        [switch]$AutoFixSubnetConflict
    )

    try {
        do {
            Show-LabMenu
            $choice = (Read-Host "  Select").Trim().ToUpperInvariant()
            switch ($choice) {
                'S' { Invoke-LabMenuCommand -Name 'setup' -Command { Invoke-LabSetupMenu -LabConfig $LabConfig -ScriptDir $ScriptDir -LabName $LabName -EffectiveMode $EffectiveMode -RunEvents $RunEvents -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict } -RunEvents $RunEvents }
                'R' {
                    Invoke-LabMenuCommand -Name 'reset' -Command {
                        $confirm = (Read-Host "  Type REBUILD to confirm").Trim()
                        if ($confirm -eq 'REBUILD') {
                            $dropNet = (Read-Host "  Remove network? (y/n)").Trim().ToLowerInvariant() -eq 'y'
                            Invoke-LabOneButtonReset -DropNetwork:$dropNet -DryRun:$false -Force:$false -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict -LabConfig $LabConfig -ScriptDir $ScriptDir -SwitchName $SwitchName -LabName $LabName -EffectiveMode $EffectiveMode -RunEvents $RunEvents
                        } else {
                            Write-Host "  Cancelled" -ForegroundColor Yellow
                        }
                    } -RunEvents $RunEvents
                }
                '1' { Invoke-LabMenuCommand -Name 'start' -Command { Invoke-LabRepoScript -BaseName 'Start-LabDay' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                '2' { Invoke-LabMenuCommand -Name 'stop' -Command { Stop-LabVMsSafe -LabName $LabName -CoreVMNames @($LabConfig.Lab.CoreVMNames); Write-LabStatus -Status OK -Message "Lab stopped" } -RunEvents $RunEvents }
                '3' { Invoke-LabMenuCommand -Name 'status' -Command { Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                '4' {
                    Invoke-LabMenuCommand -Name 'rollback' -Command {
                        if (-not (Test-LabReadySnapshot -LabName $LabName -CoreVMNames @($LabConfig.Lab.CoreVMNames))) {
                            Write-LabStatus -Status WARN -Message "LabReady snapshot not found"
                            return
                        }
                        Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                        Write-LabStatus -Status OK -Message "Restored to LabReady"
                    } -RunEvents $RunEvents
                }
                '5' { Invoke-LabMenuCommand -Name 'health' -Command { $healthArgs = Get-LabHealthArgs; Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                '6' {
                    Write-Host "  [P] Push to WS1  [S] Save Work" -ForegroundColor Cyan
                    $sub = (Read-Host "  Select").Trim().ToUpperInvariant()
                    if ($sub -eq 'P') { Invoke-LabRepoScript -BaseName 'Push-ToWS1' -ScriptDir $ScriptDir -RunEvents $RunEvents }
                    elseif ($sub -eq 'S') { Invoke-LabRepoScript -BaseName 'Save-LabWork' -ScriptDir $ScriptDir -RunEvents $RunEvents }
                }
                '7' { Invoke-LabMenuCommand -Name 'terminal' -Command { Invoke-LabRepoScript -BaseName 'Open-LabTerminal' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                '8' { Invoke-LabMenuCommand -Name 'new-project' -Command { Invoke-LabRepoScript -BaseName 'New-LabProject' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                '9' { Invoke-LabMenuCommand -Name 'test' -Command { Invoke-LabRepoScript -BaseName 'Test-OnWS1' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                'A' { Invoke-LabMenuCommand -Name 'asset-report' -Command { Invoke-LabRepoScript -BaseName 'Asset-Report' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                'F' { Invoke-LabMenuCommand -Name 'offline-bundle' -Command { Invoke-LabRepoScript -BaseName 'Build-OfflineAutomatedLabBundle' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                'O' { Invoke-LabMenuCommand -Name 'configure-role' -Command { Invoke-LabConfigureRoleMenu -ScriptDir $ScriptDir -CoreVMNames @($LabConfig.Lab.CoreVMNames) -RunEvents $RunEvents } -RunEvents $RunEvents }
                'V' { Invoke-LabMenuCommand -Name 'add-vm' -Command { Invoke-LabAddVMMenu -LabConfig $LabConfig -RunEvents $RunEvents } -RunEvents $RunEvents }
                'L' { Invoke-LabMenuCommand -Name 'add-lin1' -Command { Invoke-LabRepoScript -BaseName 'Add-LIN1' -Arguments @('-NonInteractive') -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                'C' { Invoke-LabMenuCommand -Name 'lin1-config' -Command { Invoke-LabRepoScript -BaseName 'Configure-LIN1' -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                'N' { Invoke-LabMenuCommand -Name 'ansible' -Command { Invoke-LabRepoScript -BaseName 'Install-Ansible' -Arguments @('-NonInteractive') -ScriptDir $ScriptDir -RunEvents $RunEvents } -RunEvents $RunEvents }
                'X' { break }
                default { Write-Host "  Invalid" -ForegroundColor Red; Start-Sleep -Seconds 1 }
            }
        } while ($choice -ne 'X')
    }
    catch {
        Write-Warning "Invoke-LabInteractiveMenu: interactive menu error - $_"
    }
}
