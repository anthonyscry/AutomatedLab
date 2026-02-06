<#
.SYNOPSIS
    Push-ToWS1.ps1 -- Copy project from LIN1 to WS1 via LabShare for testing
.DESCRIPTION
    Prompts for project name, copies from ~/projects/<name> to /mnt/labshare/Transfer/<name>.
    Files appear instantly on WS1 at L:\Transfer\<name>.
#>

#Requires -RunAsAdministrator

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }


$ErrorActionPreference = 'Stop'

Write-Host "`n=== PUSH TO WS1 ===" -ForegroundColor Cyan

if (-not (Ensure-VMRunning -VMNames @('DC1','LIN1'))) {
    $start = Read-Host "  DC1/LIN1 not running. Start them now? (y/n)"
    if ($start -ne 'y') { exit 0 }
    Ensure-VMRunning -VMNames @('DC1','LIN1') -AutoStart | Out-Null
}

# List available projects on LIN1
Import-Lab -Name $LabName -ErrorAction Stop

Write-Host "  Scanning projects on LIN1..." -ForegroundColor Yellow
$projects = Invoke-LabCommand -ComputerName 'LIN1' -ScriptBlock {
    ls -1 $LinuxProjectsRoot/ 2>/dev/null
} -PassThru -ErrorAction SilentlyContinue

if ($projects) {
    Write-Host "  Available projects:" -ForegroundColor Gray
    $projects | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
} else {
    Write-Host "  No projects found in ~/projects/" -ForegroundColor Yellow
}

# Prompt
$ProjectName = Read-Host "`n  Project to push"
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    Write-Host "  [ABORT] No project name given." -ForegroundColor Red
    exit 1
}

# Confirm
Write-Host "`n  Will copy:" -ForegroundColor Yellow
Write-Host "    From: LIN1:~/projects/$ProjectName/*" -ForegroundColor Gray
Write-Host "    To:   \\DC1\LabShare\Transfer\$ProjectName\" -ForegroundColor Gray
Write-Host "    View: WS1 L:\Transfer\$ProjectName\" -ForegroundColor Gray
$confirm = Read-Host "`n  Proceed? (y/n)"
if ($confirm -ne 'y') { exit 0 }

# Execute
Write-Host "`n  Copying..." -ForegroundColor Yellow
Invoke-LabCommand -ComputerName 'LIN1' -ActivityName "Push-$ProjectName" -ScriptBlock {
    param($Name)
    SRC="$LinuxProjectsRoot/$Name"
    DEST="$LinuxLabShareMount/Transfer/$Name"

    if [ ! -d "$SRC" ]; then
        echo "[FAIL] Project not found: $SRC"
        exit 1
    fi

    if ! mountpoint -q "$LinuxLabShareMount" 2>/dev/null; then
        echo "[FAIL] LabShare is not mounted at $LinuxLabShareMount"
        exit 1
    fi

    mkdir -p "$DEST"
    # Use rsync if available, otherwise cp
    if command -v rsync >/dev/null 2>&1; then
        rsync -av --delete "$SRC/" "$DEST/"
    else
        rm -rf "$DEST"/*
        cp -r "$SRC"/* "$DEST/"
    fi

    echo ""
    echo "Copied $(find "$DEST" -type f | wc -l) files to $DEST"
} -ArgumentList $ProjectName

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "  On WS1:  cd L:\Transfer\$ProjectName" -ForegroundColor Gray
Write-Host ""