# New-LabProject.ps1 -- Create a new project on LIN1 with Git + GitHub
# Prompts for project name and visibility, then:
# 1. Creates ~/projects/<n> on LIN1
# 2. Initializes Git with your identity
# 3. Creates GitHub repo via gh CLI
# 4. Creates initial commit

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

Ensure-VMsReady -VMNames @('LIN1') -NonInteractive:$NonInteractive -AutoStart:$AutoStart

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

$script = @'
#!/bin/bash
set -e

LIN_USER="__LIN_USER__"
LIN_HOME="__LIN_HOME__"
GIT_NAME="__GIT_NAME__"
GIT_EMAIL="__GIT_EMAIL__"
PROJECT_NAME="__PROJECT_NAME__"
VISIBILITY="__VISIBILITY__"
DESCRIPTION="__DESCRIPTION__"
DESC_FLAG="__DESC_FLAG__"

CMD="export HOME=$LIN_HOME
git config --global user.name \"$GIT_NAME\"
git config --global user.email \"$GIT_EMAIL\"
mkdir -p \"$LIN_HOME/projects/$PROJECT_NAME\"
cd \"$LIN_HOME/projects/$PROJECT_NAME\"

git init
git branch -M main

echo \"# $PROJECT_NAME\" > README.md
echo \"$DESCRIPTION\" >> README.md
echo \"\" > .gitignore

git add -A
git commit -m \"Initial commit\"

gh repo create \"$PROJECT_NAME\" --$VISIBILITY --source . --remote origin $DESC_FLAG --push 2>&1 || {
    echo \"[WARN] gh repo create failed. You may need to run: gh auth login\"
    echo \"       Then manually: git remote add origin https://github.com/YOUR_USER/$PROJECT_NAME.git\"
    echo \"       Then: git push -u origin main\"
}

echo \"\"
echo \"=== PROJECT CREATED ===\"
echo \"  Local:  $LIN_HOME/projects/$PROJECT_NAME\"
echo \"  Remote: https://github.com/$(gh api user -q .login 2>/dev/null || echo 'YOUR_USER')/$PROJECT_NAME\""

if [ "$(id -u)" -eq 0 ]; then
  sudo -u "$LIN_USER" -H bash -lc "$CMD"
else
  bash -lc "$CMD"
fi
'@

$scriptVars = @{
    LIN_USER = $LinuxUser
    LIN_HOME = $LinuxHome
    GIT_NAME = $GitName
    GIT_EMAIL = $GitEmail
    PROJECT_NAME = $ProjectName
    VISIBILITY = $Visibility
    DESCRIPTION = $Description
    DESC_FLAG = $descFlag
}

Write-Host "`n  Creating project on LIN1..." -ForegroundColor Yellow
Invoke-BashOnLIN1 -BashScript $script -ActivityName "Create-$ProjectName" -Variables $scriptVars | Out-Null

# Get LIN1 IP for connection info
$lin1IP = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
    Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
    Select-Object -First 1

Write-Host "`n=== DONE ===" -ForegroundColor Green
if ($lin1IP) {
    Write-Host "  SSH in:  ssh -i $SSHKey $LinuxUser@$lin1IP" -ForegroundColor Gray
} else {
    Write-Host "  Connect: Use Open-LabTerminal.ps1 to SSH into LIN1" -ForegroundColor Gray
}
Write-Host "  Then:    cd ~/projects/$ProjectName && opencode" -ForegroundColor Gray
Write-Host ""
