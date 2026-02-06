<#
.SYNOPSIS
    Save-LabWork.ps1 -- Commit, push, and optionally shut down the lab
.DESCRIPTION
    Prompts for project name and commit message, then:
      1. Commits all changes on LIN1
      2. Pushes to GitHub
      3. Optionally snapshots all VMs
      4. Optionally stops all VMs
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ProjectName = '',
    [string]$CommitMsg = '',
    [switch]$NonInteractive,
    [switch]$AutoStart,
    [switch]$TakeSnapshot,
    [switch]$StopAfterSave
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }


$ErrorActionPreference = 'Stop'

Write-Host "`n=== SAVE WORK ===" -ForegroundColor Cyan

if (-not (Ensure-VMRunning -VMNames @('LIN1'))) {
    if ($NonInteractive -or $AutoStart) {
        Ensure-VMRunning -VMNames @('LIN1') -AutoStart | Out-Null
    } else {
        $start = Read-Host "  LIN1 is not running. Start it now? (y/n)"
        if ($start -ne 'y') { exit 0 }
        Ensure-VMRunning -VMNames @('LIN1') -AutoStart | Out-Null
    }
}

if ($NonInteractive -and ([string]::IsNullOrWhiteSpace($GitName) -or [string]::IsNullOrWhiteSpace($GitEmail))) {
    throw "NonInteractive mode requires GitName and GitEmail in Lab-Config.ps1."
}

$git = Get-GitIdentity -DefaultName $GitName -DefaultEmail $GitEmail
$GitName = $git.Name
$GitEmail = $git.Email

Import-Lab -Name $LabName -ErrorAction Stop

# List projects
Write-Host "  Scanning projects on LIN1..." -ForegroundColor Yellow
$projects = Invoke-LabCommand -ComputerName 'LIN1' -ScriptBlock {
    param($ProjectsRoot)
    bash -lc "for d in '$ProjectsRoot'/*/; do if [ -d \"\$d/.git\" ]; then basename \"\$d\"; fi; done"
} -ArgumentList $LinuxProjectsRoot -PassThru -ErrorAction SilentlyContinue

if ($projects) {
    Write-Host "  Git projects:" -ForegroundColor Gray
    $projects | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
}

# Prompt for project
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    if ($NonInteractive) {
        $ProjectName = 'all'
    } else {
        $ProjectName = Read-Host "`n  Project to save (or 'all' for every project)"
    }
}
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    Write-Host "  [ABORT] No project name given." -ForegroundColor Red
    exit 1
}

# Commit message
if ([string]::IsNullOrWhiteSpace($CommitMsg) -and -not $NonInteractive) {
    $CommitMsg = Read-Host "  Commit message [save work $(Get-Date -Format 'MMdd HHmm')]"
}
if ([string]::IsNullOrWhiteSpace($CommitMsg)) {
    $CommitMsg = "save work $(Get-Date -Format 'MMdd HHmm')"
}

# Make commit message safe for bash
$CommitMsg = $CommitMsg -replace '"', "'"

# Build project list
if ($ProjectName -eq 'all') {
    $projectList = $projects
} else {
    $projectList = @($ProjectName)
}

# Commit and push each project
foreach ($proj in $projectList) {
    Write-Host "`n  [$proj] Committing and pushing..." -ForegroundColor Yellow

    Invoke-LabCommand -ComputerName 'LIN1' -ActivityName "Save-$proj" -ScriptBlock {
        param($Name, $Msg, $GName, $GEmail)
        $bash = @"
export HOME='$LinuxHome'
cd '$LinuxProjectsRoot/$Name' 2>/dev/null || { echo '[SKIP] $Name not found'; exit 0; }

git config --global user.name '$GName'
git config --global user.email '$GEmail'

if [ -z "\$(git status --porcelain)" ]; then
  echo '  No changes to commit'
else
  git add -A
  git commit -m "$Msg"
  echo '  Committed'
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push origin main 2>&1 && echo '  Pushed to GitHub' || echo '  [WARN] Push failed -- check gh auth'
else
  echo '  [SKIP] No remote configured'
fi
"@
        bash -lc $bash
    } -ArgumentList $proj, $CommitMsg, $GitName, $GitEmail
}

# Snapshot?
Write-Host ""
if ($NonInteractive) {
    $doSnapshot = if ($TakeSnapshot) { 'y' } else { 'n' }
} else {
    $doSnapshot = Read-Host "  Take a VM snapshot? (y/n) [n]"
}
if ($doSnapshot -eq 'y') {
    $snapName = "Save-$(Get-Date -Format 'MMdd-HHmm')"
    Write-Host "  Creating snapshot '$snapName'..." -ForegroundColor Yellow
    Checkpoint-LabVM -All -SnapshotName $snapName
    Write-Host "  [OK] Snapshot created" -ForegroundColor Green
}

# Shut down?
if ($NonInteractive) {
    $doStop = if ($StopAfterSave) { 'y' } else { 'n' }
} else {
    $doStop = Read-Host "  Stop all VMs? (y/n) [n]"
}
if ($doStop -eq 'y') {
    Write-Host "  Stopping VMs..." -ForegroundColor Yellow
    Stop-LabVM -All
    Write-Host "  [OK] All VMs stopped" -ForegroundColor Green
}

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host ""
