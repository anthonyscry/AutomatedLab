# Push-ToWS1.ps1 -- Copy project from LIN1 to WS1 via LabShare for testing
# Prompts for project name, copies from ~/projects/<name> to /mnt/labshare/Transfer/<name>.
# Files appear instantly on WS1 at L:\Transfer\<name>.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ProjectName = '',
    [switch]$NonInteractive,
    [switch]$AutoStart,
    [switch]$Force
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

$ErrorActionPreference = 'Stop'

Write-Host "`n=== PUSH TO WS1 ===" -ForegroundColor Cyan

Ensure-VMsReady -VMNames @('DC1','LIN1') -NonInteractive:$NonInteractive -AutoStart:$AutoStart

# List available projects on LIN1
Import-Lab -Name $LabName -ErrorAction Stop

Write-Host "  Scanning projects on LIN1..." -ForegroundColor Yellow
$projects = Invoke-LabCommand -ComputerName 'LIN1' -ScriptBlock {
    param($ProjectsRoot)
    bash -lc "ls -1 '$ProjectsRoot/' 2>/dev/null"
} -ArgumentList $LinuxProjectsRoot -PassThru -ErrorAction SilentlyContinue

if ($projects) {
    Write-Host "  Available projects:" -ForegroundColor Gray
    $projects | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
} else {
    Write-Host "  No projects found in ~/projects/" -ForegroundColor Yellow
}

# Prompt
if ([string]::IsNullOrWhiteSpace($ProjectName) -and -not $NonInteractive) {
    $ProjectName = Read-Host "`n  Project to push"
}
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    Write-Host "  [ABORT] No project name given." -ForegroundColor Red
    exit 1
}

# Confirm
Write-Host "`n  Will copy:" -ForegroundColor Yellow
Write-Host "    From: LIN1:~/projects/$ProjectName/*" -ForegroundColor Gray
Write-Host "    To:   \\DC1\LabShare\Transfer\$ProjectName\" -ForegroundColor Gray
Write-Host "    View: WS1 L:\Transfer\$ProjectName\" -ForegroundColor Gray
if (-not ($NonInteractive -or $Force)) {
    $confirm = Read-Host "`n  Proceed? (y/n)"
    if ($confirm -ne 'y') { exit 0 }
}

# Execute
Write-Host "`n  Copying..." -ForegroundColor Yellow

# Build bash script with non-interpolating here-string
$pushScript = @'
#!/bin/bash
set -e
SRC="__PROJECTS_ROOT__/__PROJECT_NAME__"
DEST="__MOUNT_PATH__/Transfer/__PROJECT_NAME__"

if [ ! -d "$SRC" ]; then
  echo "[FAIL] Project not found: $SRC"
  exit 1
fi

if ! mountpoint -q "__MOUNT_PATH__" 2>/dev/null; then
  echo "[FAIL] LabShare is not mounted at __MOUNT_PATH__"
  exit 1
fi

mkdir -p "$DEST"
if command -v rsync >/dev/null 2>&1; then
  rsync -av --delete "$SRC/" "$DEST/"
else
  rm -rf "$DEST"/*
  cp -r "$SRC"/* "$DEST/"
fi

echo ""
echo "Copied $(find "$DEST" -type f | wc -l) files to $DEST"
'@

$pushVars = @{
    PROJECTS_ROOT = $LinuxProjectsRoot
    PROJECT_NAME = $ProjectName
    MOUNT_PATH = $LinuxLabShareMount
}

Invoke-BashOnLinuxVM -VMName 'LIN1' -BashScript $pushScript -ActivityName "Push-$ProjectName" -Variables $pushVars | Out-Null

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "  On WS1:  cd L:\Transfer\$ProjectName" -ForegroundColor Gray
Write-Host ""
