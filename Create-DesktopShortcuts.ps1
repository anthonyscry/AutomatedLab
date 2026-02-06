<#
.SYNOPSIS
    Create-DesktopShortcuts.ps1 - create one-click desktop shortcuts for lab automation
.DESCRIPTION
    Creates Windows desktop shortcuts that call OpenCodeLab-App.ps1 actions.
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$AppScript = Join-Path $ScriptDir 'OpenCodeLab-App.ps1'

if (-not (Test-Path $AppScript)) {
    throw "OpenCodeLab-App.ps1 not found in $ScriptDir"
}

$DesktopPath = [Environment]::GetFolderPath('Desktop')
$Shell = New-Object -ComObject WScript.Shell

function New-LabShortcut {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Arguments,
        [string]$Description = ''
    )

    $shortcutPath = Join-Path $DesktopPath "$Name.lnk"
    $shortcut = $Shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$AppScript`" $Arguments"
    $shortcut.WorkingDirectory = $ScriptDir
    $shortcut.WindowStyle = 1
    if ($Description) { $shortcut.Description = $Description }
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
    $shortcut.Save()
    Write-Host "  [OK] $shortcutPath" -ForegroundColor Green
}

Write-Host "`n=== CREATE DESKTOP SHORTCUTS ===" -ForegroundColor Cyan

New-LabShortcut -Name 'OpenCodeLab - Setup' `
    -Arguments '-Action one-button-setup -NonInteractive' `
    -Description 'Bootstrap, deploy, start, and show lab status (noninteractive).'

New-LabShortcut -Name 'OpenCodeLab - Reset Rebuild' `
    -Arguments '-Action one-button-reset -NonInteractive -Force' `
    -Description 'Blow away lab and rebuild from scratch (noninteractive).'

New-LabShortcut -Name 'OpenCodeLab - Reset Rebuild (Network Too)' `
    -Arguments '-Action one-button-reset -RemoveNetwork -NonInteractive -Force' `
    -Description 'Blow away lab, remove switch/NAT, and rebuild (noninteractive).'

New-LabShortcut -Name 'OpenCodeLab - Control Menu' `
    -Arguments '-Action menu' `
    -Description 'Open interactive lab control menu.'

Write-Host "`nDone." -ForegroundColor Green
