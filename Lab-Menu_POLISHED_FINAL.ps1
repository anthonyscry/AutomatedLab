<#
.SYNOPSIS
    Lab-Menu.ps1 -- Main menu for OpenCode Dev Lab daily workflow
.DESCRIPTION
    One script to rule them all. Launches the appropriate workflow script.
    - LIN1: SSH (auto-discovers IP from Hyper-V)
    - DC1/WS1: PowerShell Direct (no network needed)
.NOTES
    Place all scripts in C:\LabSources\Scripts\
    Run:  .\Lab-Menu.ps1
#>

#Requires -RunAsAdministrator

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

function Get-LIN1IPForUI {
    $ip = Get-LIN1IPForUI
    if (-not $ip) {
        Write-Host "  [FAIL] Cannot find LIN1 IP. Is it running?" -ForegroundColor Red
        return $null
    }
    Write-Host "  LIN1 IP: $ip" -ForegroundColor Gray
    return $ip
}






function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   OPENCODE DEV LAB -- WORKFLOW MENU" -ForegroundColor Cyan
    Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Gray
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  STARTUP" -ForegroundColor DarkCyan
    Write-Host "   [1]  Start Lab              Boot all VMs + health check" -ForegroundColor White
    Write-Host "   [9]  Lab Status             Detailed dashboard" -ForegroundColor White
    Write-Host ""
    Write-Host "  CONNECT" -ForegroundColor DarkCyan
    Write-Host "   [S]  SSH to LIN1            In this window" -ForegroundColor White
    Write-Host "   [T]  Open Terminal          New window (LIN1/DC1/WS1/multi)" -ForegroundColor White
    Write-Host "   [D]  Connect to DC1         PowerShell Direct" -ForegroundColor White
    Write-Host "   [W]  Connect to WS1         PowerShell Direct" -ForegroundColor White
    Write-Host "   [G]  GUI Console            vmconnect (pick VM)" -ForegroundColor White
    Write-Host ""
    Write-Host "  DEVELOP" -ForegroundColor DarkCyan
    Write-Host "   [2]  New Project            Create repo on LIN1 + GitHub" -ForegroundColor White
    Write-Host "   [3]  Push to WS1            Copy project to test share" -ForegroundColor White
    Write-Host "   [4]  Test on WS1            Run scripts + AppLocker logs" -ForegroundColor White
    Write-Host "   [5]  Save Work              Commit, push, snapshot" -ForegroundColor White
    Write-Host ""
    Write-Host "  MANAGE" -ForegroundColor DarkCyan
    Write-Host "   [6]  Force GPO Update       gpupdate /force on WS1" -ForegroundColor White
    Write-Host "   [7]  Snapshot All           Create named checkpoint" -ForegroundColor White
    Write-Host "   [R]  Rollback               Restore LabReady snapshot" -ForegroundColor Yellow
    Write-Host "   [0]  Stop Lab               Shut down all VMs" -ForegroundColor White
    Write-Host ""
    Write-Host "   [Q]  Quit" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-AndPause {
    param([scriptblock]$Block)
    try { & $Block } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "`n  Press Enter to continue"
}

do {
    Show-Menu
    $choice = (Read-Host "  Select").ToUpper()

    switch ($choice) {
        '1' {
            Invoke-AndPause { & "$ScriptDir\Start-LabDay.ps1" }
        }
        '2' {
            Invoke-AndPause { & "$ScriptDir\New-LabProject.ps1" }
        }
        'S' {
            $ip = Get-LIN1IPForUI
            if ($ip) {
                Write-Host "  SSH to LIN1 (type 'exit' to return to menu)`n" -ForegroundColor Yellow
                Ensure-SSHKey -KeyPath $SSHKey
                if (-not (Ensure-VMRunning -VMNames @('LIN1'))) {
                    $start = Read-Host "  LIN1 is not running. Start it now? (y/n)"
                    if ($start -eq 'y') { Ensure-VMRunning -VMNames @('LIN1') -AutoStart | Out-Null }
                }
                & ssh -i $SSHKey -o StrictHostKeyChecking=no $LinuxUser@$ip
            } else {
                Read-Host "`n  Press Enter to continue"
            }
        }
        'T' {
            Invoke-AndPause { & "$ScriptDir\Open-LabTerminal.ps1" }
        }
        'D' {
            Write-Host "`n  Connecting to DC1 via PowerShell Direct (type 'exit' to return)..." -ForegroundColor Yellow
            Enter-PSSession -VMName DC1
        }
        'W' {
            Write-Host "`n  Connecting to WS1 via PowerShell Direct (type 'exit' to return)..." -ForegroundColor Yellow
            Enter-PSSession -VMName WS1
        }
        'G' {
            Write-Host ""
            Write-Host "   [1] DC1    [2] WS1    [3] LIN1" -ForegroundColor Gray
            $vmPick = Read-Host "  Which VM"
            $vmName = switch ($vmPick) { '1' { 'DC1' } '2' { 'WS1' } '3' { 'LIN1' } default { '' } }
            if ($vmName) {
                Write-Host "  Opening vmconnect for $vmName..." -ForegroundColor Yellow
                Start-Process vmconnect.exe -ArgumentList 'localhost', $vmName
            } else {
                Write-Host "  Invalid choice." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
        '3' {
            Invoke-AndPause { & "$ScriptDir\Push-ToWS1.ps1" }
        }
        '4' {
            Invoke-AndPause { & "$ScriptDir\Test-OnWS1.ps1" }
        }
        '5' {
            Invoke-AndPause { & "$ScriptDir\Save-LabWork.ps1" }
        }
        '6' {
            Invoke-AndPause {
                Import-Lab -Name OpenCodeLab -ErrorAction Stop
                Write-Host "  Forcing GPO update on WS1..." -ForegroundColor Yellow
                Invoke-LabCommand -ComputerName 'WS1' -ScriptBlock { gpupdate /force }
                Write-Host "  [OK] GPO updated" -ForegroundColor Green
            }
        }
        '7' {
            Invoke-AndPause {
                $snapName = Read-Host "  Snapshot name [Snap-$(Get-Date -Format 'MMdd-HHmm')]"
                if ([string]::IsNullOrWhiteSpace($snapName)) { $snapName = "Snap-$(Get-Date -Format 'MMdd-HHmm')" }
                Import-Lab -Name OpenCodeLab -ErrorAction Stop
                Checkpoint-LabVM -All -SnapshotName $snapName
                Write-Host "  [OK] Snapshot '$snapName' created" -ForegroundColor Green
            }
        }
        '9' {
            Invoke-AndPause { & "$ScriptDir\Lab-Status.ps1" }
        }
        '0' {
            Invoke-AndPause {
                $confirm = Read-Host "  Stop all VMs? (y/n)"
                if ($confirm -eq 'y') {
                    Write-Host "  Stopping..." -ForegroundColor Yellow
                    try {
                        Import-Lab -Name OpenCodeLab -ErrorAction Stop
                        Stop-LabVM -All
                    } catch {
                        Get-VM | Where-Object { $_.Name -in 'DC1','WS1','LIN1' } | Stop-VM -Force
                    }
                    Write-Host "  [OK] All VMs stopped" -ForegroundColor Green
                }
            }
        }
        'R' {
            Invoke-AndPause {
                Write-Host "`n  WARNING: This rolls ALL VMs back to LabReady." -ForegroundColor Red
                Write-Host "  Any unsaved work will be LOST." -ForegroundColor Red
                $confirm = Read-Host "  Type 'ROLLBACK' to confirm"
                if ($confirm -eq 'ROLLBACK') {
                    Import-Lab -Name OpenCodeLab -ErrorAction Stop
                    Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                    Write-Host "  [OK] Rolled back to LabReady" -ForegroundColor Green
                } else {
                    Write-Host "  [ABORT] Cancelled" -ForegroundColor Yellow
                }
            }
        }
        'Q' { break }
        default {
            Write-Host "  Invalid choice." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne 'Q')

Write-Host "`n  Goodbye.`n" -ForegroundColor Gray