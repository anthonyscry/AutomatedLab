# Open-LabTerminal.ps1 -- Open new terminal windows to lab VMs
# Opens a NEW PowerShell window with a connection to the selected VM.
# - LIN1: SSH (auto-discovers IP from Hyper-V)
# - DC1/WS1: PowerShell Direct (Enter-PSSession -VMName)
# Supports multiple simultaneous sessions (each in its own window).
# Uses Windows Terminal tabs if wt.exe is available.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet('LIN1','DC1','WS1','')]
    [string]$Target = ''
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

function Get-LIN1IPForTerminal {
    $ip = Get-LIN1IPv4
    if (-not $ip) {
        Write-Host "  [FAIL] Cannot find LIN1 IP. Is it running?" -ForegroundColor Red
        Write-Host "  Try: Get-VMNetworkAdapter -VMName LIN1 | Select IPAddresses" -ForegroundColor Yellow
        return $null
    }
    return $ip
}

function Open-NewTerminal {
    param(
        [string]$Title,
        [string]$Command
    )
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        & wt.exe new-tab --title $Title powershell.exe -NoExit -Command $Command
    } else {
        Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle = '$Title'; $Command"
    }
}

if ([string]::IsNullOrWhiteSpace($Target)) {
    Write-Host "`n=== OPEN TERMINAL ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   [1]  LIN1  (SSH)                -- OpenCode / Claude Code" -ForegroundColor White
    Write-Host "   [2]  DC1   (PowerShell Direct)  -- Domain Controller" -ForegroundColor White
    Write-Host "   [3]  WS1   (PowerShell Direct)  -- Test Client" -ForegroundColor White
    Write-Host "   [4]  LIN1  x2                   -- Two SSH sessions" -ForegroundColor White
    Write-Host "   [5]  All   (LIN1 + DC1 + WS1)   -- One of each" -ForegroundColor White
    Write-Host ""
    $pick = Read-Host "  Select"

    switch ($pick) {
        '1' { $Target = 'LIN1' }
        '2' { $Target = 'DC1' }
        '3' { $Target = 'WS1' }
        '4' {
            $ip = Get-LIN1IPForTerminal
            if (-not $ip) { return }
            Write-Host "  LIN1 IP: $ip" -ForegroundColor Gray
            Open-NewTerminal -Title "LIN1 (1)" -Command "ssh -i '$SSHKey' -o StrictHostKeyChecking=no $LinuxUser@$ip"
            Start-Sleep -Milliseconds 500
            Open-NewTerminal -Title "LIN1 (2)" -Command "ssh -i '$SSHKey' -o StrictHostKeyChecking=no $LinuxUser@$ip"
            Write-Host "  [OK] Opened 2 LIN1 sessions" -ForegroundColor Green
            return
        }
        '5' {
            $ip = Get-LIN1IPForTerminal
            if (-not $ip) { return }
            Write-Host "  LIN1 IP: $ip" -ForegroundColor Gray
            Open-NewTerminal -Title "LIN1 (SSH)" -Command "ssh -i '$SSHKey' -o StrictHostKeyChecking=no $LinuxUser@$ip"
            Start-Sleep -Milliseconds 500
            Open-NewTerminal -Title "DC1 (PS Direct)" -Command "Enter-PSSession -VMName DC1"
            Start-Sleep -Milliseconds 500
            Open-NewTerminal -Title "WS1 (PS Direct)" -Command "Enter-PSSession -VMName WS1"
            Write-Host "  [OK] Opened LIN1 + DC1 + WS1 sessions" -ForegroundColor Green
            return
        }
        default {
            Write-Host "  Invalid choice." -ForegroundColor Red
            return
        }
    }
}

switch ($Target) {
    'LIN1' {
        $ip = Get-LIN1IPForTerminal
        if (-not $ip) { return }
        Write-Host "  LIN1 IP: $ip" -ForegroundColor Gray
        Open-NewTerminal -Title "LIN1 (SSH)" -Command "ssh -i '$SSHKey' -o StrictHostKeyChecking=no $LinuxUser@$ip"
        Write-Host "  [OK] Opened LIN1 SSH session" -ForegroundColor Green
    }
    'DC1' {
        Open-NewTerminal -Title "DC1 (PS Direct)" -Command "Enter-PSSession -VMName DC1"
        Write-Host "  [OK] Opened DC1 PowerShell Direct session" -ForegroundColor Green
    }
    'WS1' {
        Open-NewTerminal -Title "WS1 (PS Direct)" -Command "Enter-PSSession -VMName WS1"
        Write-Host "  [OK] Opened WS1 PowerShell Direct session" -ForegroundColor Green
    }
}
