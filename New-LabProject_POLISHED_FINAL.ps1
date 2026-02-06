<#
.SYNOPSIS
    New-LabProject.ps1 -- Create a new project on LIN1 with Git + GitHub
.DESCRIPTION
    Prompts for project name and visibility, then:
      1. Creates ~/projects/<n> on LIN1
      2. Initializes Git with your identity
      3. Creates GitHub repo via gh CLI
      4. Creates initial commit
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$ProjectName,
    [ValidateSet('public','private')]
    [string]$Visibility = 'private',
    [string]$Description = '',
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

Write-Host "`n=== NEW PROJECT ===" -ForegroundColor Cyan

# Ensure LIN1 is running
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

# Prompt for project name
if ([string]::IsNullOrWhiteSpace($ProjectName) -and -not $NonInteractive) {
    $ProjectName = Read-Host "  Project name (e.g. GA-AppLocker-v2)"
}
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    Write-Host "  [ABORT] No project name given." -ForegroundColor Red
    exit 1
}

# Sanitize -- remove spaces, special chars
$ProjectName = $ProjectName -replace '[^a-zA-Z0-9_\-\.]', '-'
Write-Host "  Project: $ProjectName" -ForegroundColor Green

# Prompt for visibility
if (-not $NonInteractive) {
    $visInput = Read-Host "  GitHub visibility? (public/private) [$Visibility]"
    if (-not [string]::IsNullOrWhiteSpace($visInput)) { $Visibility = $visInput }
    if ($Visibility -notin 'public', 'private') {
        Write-Host "  [ABORT] Must be 'public' or 'private'." -ForegroundColor Red
        exit 1
    }
}

# Prompt for description (optional)
if ([string]::IsNullOrWhiteSpace($Description) -and -not $NonInteractive) {
    $Description = Read-Host "  Short description (optional)"
}

# Confirm
Write-Host "`n  Summary:" -ForegroundColor Yellow
Write-Host "    Name:        $ProjectName"
Write-Host "    Visibility:  $Visibility"
Write-Host "    Description: $(if ($Description) { $Description } else { '(none)' })"
Write-Host "    Git user:    $GitName <$GitEmail>"
if (-not ($NonInteractive -or $Force)) {
    $confirm = Read-Host "`n  Proceed? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "  [ABORT] Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Import lab
Import-Lab -Name $LabName -ErrorAction Stop

# Build the bash commands
$descFlag = if ($Description) { "--description `"$Description`"" } else { "" }

$script = @"
set -e
export HOME=$LinuxHome

# Git identity
git config --global user.name "$GitName"
git config --global user.email "$GitEmail"

# Create project
mkdir -p ~/projects/$ProjectName
cd ~/projects/$ProjectName

# Initialize
git init
git branch -M main

# Create starter files
echo "# $ProjectName" > README.md
echo "$Description" >> README.md
echo "" > .gitignore

# Initial commit
git add -A
git commit -m "Initial commit"

# Create GitHub repo
gh repo create $ProjectName --$Visibility --source . --remote origin $descFlag --push 2>&1 || {
    echo "[WARN] gh repo create failed. You may need to run: gh auth login"
    echo "       Then manually: git remote add origin https://github.com/YOUR_USER/$ProjectName.git"
    echo "       Then: git push -u origin main"
}

echo ""
echo "=== PROJECT CREATED ==="
echo "  Local:  ~/projects/$ProjectName"
echo "  Remote: https://github.com/`$(gh api user -q .login 2>/dev/null || echo 'YOUR_USER')/$ProjectName"
"@

Write-Host "`n  Creating project on LIN1..." -ForegroundColor Yellow

# Write script to temp file and copy to LIN1
$tempScript = "$env:TEMP\new-project-$ProjectName.sh"
$script | Set-Content -Path $tempScript -Encoding ASCII -Force

Copy-LabFileItem -Path $tempScript -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

$scriptFileName = "new-project-$ProjectName.sh"
Invoke-LabCommand -ComputerName 'LIN1' -ActivityName "Create-$ProjectName" -ScriptBlock {
    param($ScriptFile)
    chmod +x "/tmp/$ScriptFile"
    su - $LinuxUser -c "bash /tmp/$ScriptFile"
} -ArgumentList $scriptFileName

Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

# Get LIN1 IP for connection info
$lin1IP = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
    Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
    Select-Object -First 1

Write-Host "`n=== DONE ===" -ForegroundColor Green
if ($lin1IP) {
    Write-Host "  SSH in:  ssh -i $SSHKey $LinuxUser@$lin1IP" -ForegroundColor Gray
} else {
    Write-Host "  Connect: Use Lab Menu > SSH to LIN1" -ForegroundColor Gray
}
Write-Host "  Then:    cd ~/projects/$ProjectName && opencode" -ForegroundColor Gray
Write-Host ""
