# Test-OnWS1.ps1 -- Run a script from the LabShare on WS1
# Prompts for project and script name, runs it on WS1 from L:\Transfer.
# Also offers to check AppLocker event logs after execution.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ProjectName = '',
    [string]$ScriptName = '',
    [switch]$NonInteractive,
    [switch]$AutoStart,
    [switch]$CheckLogs,
    [switch]$ForceGPO
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $RepoRoot 'Lab-Config.ps1'
$CommonPath = Join-Path $RepoRoot 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }


$ErrorActionPreference = 'Stop'

Write-Host "`n=== TEST ON WS1 ===" -ForegroundColor Cyan

Ensure-VMsReady -VMNames @('DC1','WS1') -NonInteractive:$NonInteractive -AutoStart:$AutoStart

Import-Lab -Name $LabName -ErrorAction Stop

# List what's in the Transfer folder on DC1
Write-Host "  Scanning L:\Transfer\ ..." -ForegroundColor Yellow
$transferContents = Invoke-LabCommand -ComputerName 'DC1' -ScriptBlock {
    if (Test-Path 'C:\LabShare\Transfer') {
        Get-ChildItem 'C:\LabShare\Transfer' -Directory | Select-Object -ExpandProperty Name
    }
} -PassThru -ErrorAction SilentlyContinue

if ($transferContents) {
    Write-Host "  Available in Transfer:" -ForegroundColor Gray
    $transferContents | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
} else {
    Write-Host "  Transfer folder is empty. Run Push-ToWS1.ps1 first." -ForegroundColor Yellow
    exit 0
}

# Prompt for project
if ([string]::IsNullOrWhiteSpace($ProjectName) -and -not $NonInteractive) {
    $ProjectName = Read-Host "`n  Project folder"
}
if ([string]::IsNullOrWhiteSpace($ProjectName)) { exit 0 }

# List scripts in that folder
Write-Host "  Scanning scripts in $ProjectName..." -ForegroundColor Yellow
$scripts = Invoke-LabCommand -ComputerName 'DC1' -ScriptBlock {
    param($Name)
    $path = "C:\LabShare\Transfer\$Name"
    if (Test-Path $path) {
        Get-ChildItem $path -Filter '*.ps1' -Recurse | ForEach-Object {
            $_.FullName.Replace("C:\LabShare\Transfer\$Name\", '')
        }
    }
} -ArgumentList $ProjectName -PassThru -ErrorAction SilentlyContinue

if ($scripts) {
    Write-Host "  PowerShell scripts found:" -ForegroundColor Gray
    $scripts | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
} else {
    Write-Host "  No .ps1 files found in $ProjectName" -ForegroundColor Yellow
}

if ([string]::IsNullOrWhiteSpace($ScriptName) -and -not $NonInteractive) {
    $ScriptName = Read-Host "`n  Script to run (relative path, or Enter to skip)"
}

if (-not [string]::IsNullOrWhiteSpace($ScriptName)) {
    Write-Host "`n  Running on WS1: L:\Transfer\$ProjectName\$ScriptName" -ForegroundColor Yellow
    Write-Host "  ---" -ForegroundColor DarkGray

    Invoke-LabCommand -ComputerName 'WS1' -ActivityName "Test-$ScriptName" -ScriptBlock {
        param($Proj, $Script)
        Set-Location "L:\Transfer\$Proj"
        Write-Host "  Working directory: $(Get-Location)" -ForegroundColor Gray
        & ".\$Script"
    } -ArgumentList $ProjectName, $ScriptName

    Write-Host "  ---" -ForegroundColor DarkGray
}

# AppLocker logs?
$checkLogs = if ($NonInteractive) { if ($CheckLogs) { 'y' } else { 'n' } } else { Read-Host "`n  Check AppLocker event logs? (y/n) [n]" }
if ($checkLogs -eq 'y') {
    Write-Host "`n  Recent AppLocker events on WS1:" -ForegroundColor Yellow
    Write-Host "  ---" -ForegroundColor DarkGray

    Invoke-LabCommand -ComputerName 'WS1' -ActivityName 'AppLocker-Logs' -ScriptBlock {
        $logs = @(
            'Microsoft-Windows-AppLocker/EXE and DLL',
            'Microsoft-Windows-AppLocker/MSI and Script',
            'Microsoft-Windows-AppLocker/Packaged app-Deployment',
            'Microsoft-Windows-AppLocker/Packaged app-Execution'
        )
        foreach ($log in $logs) {
            $events = Get-WinEvent -LogName $log -MaxEvents 5 -ErrorAction SilentlyContinue
            if ($events) {
                Write-Host "  [$log]" -ForegroundColor Cyan
                $events | Format-Table -Property TimeCreated, Id, Message -AutoSize -Wrap
            }
        }
    }
    Write-Host "  ---" -ForegroundColor DarkGray
}

# GPO update?
$doGPO = if ($NonInteractive) { if ($ForceGPO) { 'y' } else { 'n' } } else { Read-Host "  Force GPO update on WS1? (y/n) [n]" }
if ($doGPO -eq 'y') {
    Invoke-LabCommand -ComputerName 'WS1' -ScriptBlock { gpupdate /force }
    Write-LabStatus -Status OK -Message "GPO updated"
}

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host ""
