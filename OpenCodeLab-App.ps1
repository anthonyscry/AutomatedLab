# OpenCodeLab-App.ps1 - lightweight orchestrator for AutomatedLab workflow
# Single entry point for setup, daily operations, and full teardown.
# Uses existing scripts in this repository and adds a safe "blow away" path.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet(
        'menu',
        'setup',
        'one-button-setup',
        'one-button-reset',
        'preflight',
        'bootstrap',
        'deploy',
        'add-lin1',
        'lin1-config',
        'ansible',
        'health',
        'start',
        'status',
        'terminal',
        'new-project',
        'push',
        'test',
        'save',
        'stop',
        'rollback',
        'blow-away'
    )]
    [string]$Action = 'menu',
    [switch]$Force,
    [switch]$RemoveNetwork,
    [switch]$NonInteractive,
    [switch]$CoreOnly = $true,
    [string]$DefaultsFile,
    [switch]$DryRun,
    [int]$LogRetentionDays = 14
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }

$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $CommonPath) { . $CommonPath }

# Alias for backward compatibility with existing code
Set-Alias -Name Remove-VMHardSafe -Value Remove-HyperVVMStale -Scope Script

if (-not (Get-Variable -Name LabName -ErrorAction SilentlyContinue)) { $LabName = 'OpenCodeLab' }
if (-not (Get-Variable -Name LabVMs -ErrorAction SilentlyContinue)) { $LabVMs = @('DC1', 'WSUS1', 'WS1') }
if (-not (Get-Variable -Name LabPath -ErrorAction SilentlyContinue)) { $LabPath = "C:\AutomatedLab\$LabName" }
if (-not (Get-Variable -Name LabSwitch -ErrorAction SilentlyContinue)) { $LabSwitch = 'OpenCodeLabSwitch' }
if (-not (Get-Variable -Name NatName -ErrorAction SilentlyContinue)) { $NatName = 'OpenCodeLabSwitchNAT' }

$SwitchName = $LabSwitch
$RunStart = Get-Date
$RunId = (Get-Date -Format 'yyyyMMdd-HHmmss')
$RunLogRoot = 'C:\LabSources\Logs'
$RunEvents = New-Object System.Collections.Generic.List[object]

function Add-RunEvent {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Status,
        [string]$Message = ''
    )

    $RunEvents.Add([pscustomobject]@{
        Time = (Get-Date).ToString('o')
        Step = $Step
        Status = $Status
        Message = $Message
    }) | Out-Null
}

function Write-RunArtifacts {
    param(
        [Parameter(Mandatory)][bool]$Success,
        [string]$ErrorMessage = ''
    )

    if (-not (Test-Path $RunLogRoot)) {
        New-Item -Path $RunLogRoot -ItemType Directory -Force | Out-Null
    }

    $ended = Get-Date
    $duration = [int]($ended - $RunStart).TotalSeconds
    $baseName = "OpenCodeLab-Run-$RunId"
    $jsonPath = Join-Path $RunLogRoot "$baseName.json"
    $txtPath = Join-Path $RunLogRoot "$baseName.txt"

    $report = [pscustomobject]@{
        run_id = $RunId
        action = $Action
        noninteractive = [bool]$NonInteractive
        core_only = [bool]$CoreOnly
        force = [bool]$Force
        remove_network = [bool]$RemoveNetwork
        dry_run = [bool]$DryRun
        defaults_file = $DefaultsFile
        started_utc = $RunStart.ToUniversalTime().ToString('o')
        ended_utc = $ended.ToUniversalTime().ToString('o')
        duration_seconds = $duration
        success = $Success
        error = $ErrorMessage
        host = $env:COMPUTERNAME
        user = "$env:USERDOMAIN\$env:USERNAME"
        events = $RunEvents
    }

    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    $lines = @(
        "run_id: $RunId",
        "action: $Action",
        "core_only: $CoreOnly",
        "success: $Success",
        "started_utc: $($RunStart.ToUniversalTime().ToString('o'))",
        "ended_utc: $($ended.ToUniversalTime().ToString('o'))",
        "duration_seconds: $duration",
        "error: $ErrorMessage",
        "host: $env:COMPUTERNAME",
        "user: $env:USERDOMAIN\$env:USERNAME",
        "events:"
    )

    foreach ($runEvent in $RunEvents) {
        $lines += "- [$($runEvent.Time)] $($runEvent.Step) :: $($runEvent.Status) :: $($runEvent.Message)"
    }

    $lines | Set-Content -Path $txtPath -Encoding UTF8
    Write-Host "`n  Run report: $jsonPath" -ForegroundColor DarkGray
    Write-Host "  Run summary: $txtPath" -ForegroundColor DarkGray
}

function Invoke-LogRetention {
    if ($LogRetentionDays -lt 1) { return }
    if (-not (Test-Path $RunLogRoot)) { return }

    $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
    Get-ChildItem -Path $RunLogRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Test-LabReadySnapshot {
    param([string[]]$VMNames)

    try {
        Ensure-LabImported
        $targets = @()
        if ($VMNames -and $VMNames.Count -gt 0) {
            $targets = @($VMNames)
        } elseif (Get-Command Get-ExpectedVMs -ErrorAction SilentlyContinue) {
            $targets = @(Get-ExpectedVMs)
        } else {
            $targets = @($LabVMs)
        }

        foreach ($vmName in $targets) {
            $snap = Get-VMSnapshot -VMName $vmName -Name 'LabReady' -ErrorAction SilentlyContinue
            if (-not $snap) {
                return $false
            }
        }
        return $true
    } catch {
        return $false
    }
}

if ($DefaultsFile) {
    if (-not (Test-Path $DefaultsFile)) {
        throw "Defaults file not found: $DefaultsFile"
    }

    $defaults = Get-Content -Raw -Path $DefaultsFile | ConvertFrom-Json
    if ($null -ne $defaults.RemoveNetwork) { $RemoveNetwork = [bool]$defaults.RemoveNetwork }
    if ($null -ne $defaults.Force) { $Force = [bool]$defaults.Force }
    if ($null -ne $defaults.NonInteractive) { $NonInteractive = [bool]$defaults.NonInteractive }
    if ($null -ne $defaults.CoreOnly) { $CoreOnly = [bool]$defaults.CoreOnly }
}

function Resolve-ScriptPath {
    param([Parameter(Mandatory)][string]$BaseName)
    # Search root first, then Scripts/ subfolder
    $path = Join-Path $ScriptDir "$BaseName.ps1"
    if (Test-Path $path) { return $path }
    $altPath = Join-Path $ScriptDir "Scripts\$BaseName.ps1"
    if (Test-Path $altPath) { return $altPath }
    throw "Script not found: $path (also checked Scripts\$BaseName.ps1)"
}

function Convert-ArgumentArrayToSplat {
    param([string[]]$ArgumentList)

    $splat = @{}
    for ($i = 0; $i -lt $ArgumentList.Count; $i++) {
        $token = $ArgumentList[$i]
        if (-not $token.StartsWith('-')) {
            throw "Unsupported argument token '$token'. Use named parameters (for example -NonInteractive)."
        }

        $name = $token.TrimStart('-')
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Invalid argument token '$token'."
        }

        $nextIsValue = ($i + 1 -lt $ArgumentList.Count) -and (-not $ArgumentList[$i + 1].StartsWith('-'))
        if ($nextIsValue) {
            $splat[$name] = $ArgumentList[$i + 1]
            $i++
        } else {
            $splat[$name] = $true
        }
    }

    return $splat
}

function Invoke-RepoScript {
    param(
        [Parameter(Mandatory)][string]$BaseName,
        [string[]]$Arguments
    )

    $path = Resolve-ScriptPath -BaseName $BaseName
    $argText = if ($Arguments -and $Arguments.Count -gt 0) { $Arguments -join ' ' } else { '' }
    Add-RunEvent -Step $BaseName -Status 'start' -Message $argText
    Write-Host "  Running: $([System.IO.Path]::GetFileName($path))" -ForegroundColor Gray
    try {
        if ($Arguments -and $Arguments.Count -gt 0) {
            $scriptSplat = Convert-ArgumentArrayToSplat -ArgumentList $Arguments
            & $path @scriptSplat
        } else {
            & $path
        }
        Add-RunEvent -Step $BaseName -Status 'ok' -Message 'completed'
    } catch {
        Add-RunEvent -Step $BaseName -Status 'fail' -Message $_.Exception.Message
        throw
    }
}

function Get-ExpectedVMs {
    return @($LabVMs)
}

function Get-PreflightArgs {
    return @()
}

function Get-BootstrapArgs {
    $scriptArgs = @()
    if ($NonInteractive) { $scriptArgs += '-NonInteractive' }
    return $scriptArgs
}

function Get-DeployArgs {
    $scriptArgs = @()
    if ($NonInteractive) { $scriptArgs += '-NonInteractive' }
    return $scriptArgs
}

function Get-HealthArgs {
    return @()
}

function Ensure-LabImported {
    if (Get-Module -Name AutomatedLab -ErrorAction SilentlyContinue) {
        # Module already loaded; just ensure lab is imported
        try {
            $lab = Get-Lab -ErrorAction SilentlyContinue
            if ($lab -and $lab.Name -eq $LabName) { return }
        } catch {
            Write-Verbose "Lab query failed (expected if lab not yet created): $_"
        }
    }

    try {
        Import-Module AutomatedLab -ErrorAction Stop | Out-Null
    } catch {
        throw "AutomatedLab module is not installed. Run setup first."
    }

    try {
        Import-Lab -Name $LabName -ErrorAction Stop | Out-Null
    } catch {
        throw "Lab '$LabName' is not registered. Run setup first."
    }
}

function Stop-LabVMsSafe {
    try {
        Ensure-LabImported
        Stop-LabVM -All -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Get-VM -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in $LabVMs -and $_.State -eq 'Running' } |
            Stop-VM -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BlowAway {
    param(
        [switch]$BypassPrompt,
        [switch]$DropNetwork,
        [switch]$Simulate
    )

    if ($Simulate) {
        Write-Host "`n=== DRY RUN: BLOW AWAY LAB ===" -ForegroundColor Yellow
        Write-Host "  Would stop lab VMs: $($LabVMs -join ', ')" -ForegroundColor DarkGray
        Write-Host "  Would remove lab definition: $LabName" -ForegroundColor DarkGray
        Write-Host "  Would remove lab files: $LabPath" -ForegroundColor DarkGray
        if ($DropNetwork) {
            Write-Host "  Would remove network: $SwitchName / $NatName" -ForegroundColor DarkGray
        }
        Add-RunEvent -Step 'blow-away' -Status 'dry-run' -Message 'No changes made'
        return
    }

    Write-Host "`n=== BLOW AWAY LAB ===" -ForegroundColor Red
    Write-Host "  This will stop VMs, remove lab definition, and delete local lab files." -ForegroundColor Yellow
    if ($DropNetwork) {
        Write-Host "  Network objects ($SwitchName / $NatName) will also be removed." -ForegroundColor Yellow
    }

    if (-not $BypassPrompt) {
        $confirm = Read-Host "  Type BLOW-IT-AWAY to continue"
        if ($confirm -ne 'BLOW-IT-AWAY') {
            Write-Host "  [ABORT] Cancelled" -ForegroundColor Yellow
            return
        }
    }

    Write-Host "`n  [1/5] Stopping lab VMs..." -ForegroundColor Cyan
    Stop-LabVMsSafe

    Write-Host "  [2/5] Removing AutomatedLab definition..." -ForegroundColor Cyan
    try {
        Import-Module AutomatedLab -ErrorAction SilentlyContinue | Out-Null

        # Remove-Lab can emit noisy non-terminating errors for already-missing
        # metadata files (for example Network_<switch>.xml). Those are benign
        # during blow-away, so suppress raw error stream and continue cleanup.
        Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 2>$null
    } catch {
        Write-LabStatus -Status WARN -Message "Remove-Lab returned: $($_.Exception.Message)"
    }

    Write-Host "  [3/5] Removing Hyper-V VMs/checkpoints if present..." -ForegroundColor Cyan
    $allLabVMs = @($LabVMs) + @('LIN1')
    foreach ($vmName in $allLabVMs) {
        if (Remove-VMHardSafe -VMName $vmName) {
            Write-Host "    removed VM $vmName" -ForegroundColor Gray
        } elseif (Hyper-V\Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
            Write-LabStatus -Status WARN -Message "Could not fully remove VM $vmName. Reboot host, then run blow-away again." -Indent 2
        }
    }

    $remainingLabVms = foreach ($vmName in $allLabVMs) {
        Hyper-V\Get-VM -Name $vmName -ErrorAction SilentlyContinue
    }
    if (-not $remainingLabVms) {
        Write-LabStatus -Status OK -Message "No lab VMs remain in Hyper-V inventory." -Indent 2

        # Hyper-V Manager can still show phantom entries until management services/UI refresh.
        try {
            Get-Process vmconnect -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Get-Process mmc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

            Stop-Service vmcompute -Force -ErrorAction SilentlyContinue
            Stop-Service vmms -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Start-Service vmms -ErrorAction Stop
            Start-Service vmcompute -ErrorAction SilentlyContinue

            Write-LabStatus -Status OK -Message "Refreshed Hyper-V management services and closed stale UI sessions." -Indent 2
        } catch {
            Write-LabStatus -Status WARN -Message "Could not fully refresh Hyper-V services automatically: $($_.Exception.Message)" -Indent 2
        }

        $ghostCheck = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
        if (-not $ghostCheck) {
            Write-LabStatus -Status OK -Message "PowerShell confirms LIN1 is not present." -Indent 2
        }

        Write-LabStatus -Status NOTE -Message "If Hyper-V Manager still shows LIN1 now, reboot the host to clear VMMS cache." -Indent 2
        Write-Host "           Then open Hyper-V Manager and refresh the server node." -ForegroundColor DarkGray
    }

    Write-Host "  [4/5] Removing lab files..." -ForegroundColor Cyan
    if (Test-Path $LabPath) {
        Remove-Item -Path $LabPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    removed $LabPath" -ForegroundColor Gray
    }

    Write-Host "  [5/5] Cleaning network artifacts (optional)..." -ForegroundColor Cyan
    if ($DropNetwork) {
        $nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
        if ($nat) {
            Remove-NetNat -Name $NatName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "    removed NAT $NatName" -ForegroundColor Gray
        }

        $sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
        if ($sw) {
            Remove-VMSwitch -Name $SwitchName -Force -ErrorAction SilentlyContinue
            Write-Host "    removed switch $SwitchName" -ForegroundColor Gray
        }
    } else {
        Write-Host "    skipped (use -RemoveNetwork to include)" -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-LabStatus -Status OK -Message 'Lab teardown complete.'
    Write-Host "  Run '.\OpenCodeLab-App.ps1 -Action setup' to rebuild." -ForegroundColor Gray
}

function Invoke-OneButtonSetup {
    Write-Host "`n=== ONE-BUTTON SETUP ===" -ForegroundColor Cyan
    Write-Host "  Mode: WINDOWS CORE (DC1 + WSUS1 + WS1)" -ForegroundColor Green
    Write-Host "  Bootstrapping prerequisites + deploying lab + start + status" -ForegroundColor Gray

    $preflightArgs = Get-PreflightArgs
    $bootstrapArgs = Get-BootstrapArgs

    Invoke-RepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs
    Invoke-RepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs

    # Verify expected VMs exist after bootstrap (bootstrap chains into deploy)
    $expectedVMs = Get-ExpectedVMs
    $missingVMs = $expectedVMs | Where-Object { -not (Hyper-V\Get-VM -Name $_ -ErrorAction SilentlyContinue) }
    if ($missingVMs) {
        throw "VMs not found after bootstrap: $($missingVMs -join ', '). Deploy may have failed."
    }

    Invoke-RepoScript -BaseName 'Start-LabDay'
    Invoke-RepoScript -BaseName 'Lab-Status'

    $healthArgs = Get-HealthArgs
    try {
        Invoke-RepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs
        Write-LabStatus -Status OK -Message "Post-deploy health gate passed"
    } catch {
        Write-LabStatus -Status FAIL -Message "Post-deploy health gate failed"
        Write-Host "  Attempting automatic rollback to LabReady..." -ForegroundColor Yellow
        try {
            Ensure-LabImported
            if (-not (Test-LabReadySnapshot)) {
                Add-RunEvent -Step 'rollback' -Status 'fail' -Message 'LabReady snapshot missing'
                Write-LabStatus -Status WARN -Message "LabReady snapshot missing. Cannot auto-rollback."
                Write-Host "  Run deploy once to recreate LabReady checkpoint." -ForegroundColor Yellow
            } else {
                Add-RunEvent -Step 'rollback' -Status 'start' -Message 'Restore-LabVMSnapshot LabReady'
                Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                Add-RunEvent -Step 'rollback' -Status 'ok' -Message 'LabReady restored'
                Write-LabStatus -Status OK -Message "Automatic rollback completed"
                Invoke-RepoScript -BaseName 'Lab-Status'
            }
        } catch {
            Add-RunEvent -Step 'rollback' -Status 'fail' -Message $_.Exception.Message
            Write-LabStatus -Status WARN -Message "Automatic rollback failed: $($_.Exception.Message)"
        }
        throw
    }

    Write-Host ''
    Write-LabStatus -Status OK -Message 'One-button setup complete.'
}

function Invoke-OneButtonReset {
    param([switch]$DropNetwork)

    Write-Host "`n=== ONE-BUTTON RESET/REBUILD ===" -ForegroundColor Red
    if ($DryRun) {
        Write-Host "  Dry run enabled: reset/rebuild actions will not execute." -ForegroundColor Yellow
        Invoke-BlowAway -BypassPrompt -DropNetwork:$DropNetwork -Simulate
        Add-RunEvent -Step 'one-button-reset' -Status 'dry-run' -Message 'No changes made'
        return
    }

    Invoke-BlowAway -BypassPrompt -DropNetwork:$DropNetwork
    Invoke-OneButtonSetup
}

function Invoke-Setup {
    $preflightArgs = Get-PreflightArgs
    $bootstrapArgs = Get-BootstrapArgs

    Invoke-RepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs
    Invoke-RepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs
}

function Pause-Menu {
    Read-Host "`n  Press Enter to continue" | Out-Null
}

function Invoke-MenuCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Command,
        [switch]$NoPause
    )

    Add-RunEvent -Step "menu:$Name" -Status 'start' -Message 'interactive'
    try {
        & $Command
        Add-RunEvent -Step "menu:$Name" -Status 'ok' -Message 'completed'
    } catch {
        Add-RunEvent -Step "menu:$Name" -Status 'fail' -Message $_.Exception.Message
        Write-LabStatus -Status FAIL -Message "$($_.Exception.Message)"
    }

    if (-not $NoPause) {
        Pause-Menu
    }
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   OPENCODE LAB APP" -ForegroundColor Cyan
    Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Gray
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  SETUP" -ForegroundColor DarkCyan
    Write-Host "   [A] One-Button Setup (DC1 + WSUS1 + WS1)" -ForegroundColor Green
    Write-Host "       Automated: Bootstrap -> Deploy -> Start -> Health check" -ForegroundColor DarkGray
    Write-Host "       Duration: 45-90 min | Requires: ISOs in C:\LabSources\ISOs" -ForegroundColor DarkGray
    Write-Host "   [B] Bootstrap + Deploy (Windows topology)" -ForegroundColor White
    Write-Host "       Duration: 30-60 min | Requires: ISOs, Hyper-V enabled" -ForegroundColor DarkGray
    Write-Host "   [D] Deploy only (skip prerequisite check)" -ForegroundColor White
    Write-Host ""
    Write-Host "  OPERATE" -ForegroundColor DarkCyan
    Write-Host "   [H] Health Gate" -ForegroundColor White
    Write-Host "   [1] Start Lab" -ForegroundColor White
    Write-Host "   [2] Lab Status" -ForegroundColor White
    Write-Host "   [3] Open Terminal" -ForegroundColor White
    Write-Host "   [4] New Project" -ForegroundColor White
    Write-Host "   [5] Push to WS1" -ForegroundColor White
    Write-Host "   [6] Test on WS1" -ForegroundColor White
    Write-Host "   [7] Save Work" -ForegroundColor White
    Write-Host "   [8] Stop Lab" -ForegroundColor White
    Write-Host "   [9] Rollback to LabReady" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  LINUX" -ForegroundColor DarkCyan
    Write-Host "   [L] Add LIN1 (Ubuntu VM)" -ForegroundColor White
    Write-Host "       Creates Ubuntu 24.04 VM with cloud-init autoinstall" -ForegroundColor DarkGray
    Write-Host "       Duration: 15-30 min | Requires: Ubuntu ISO, running DC1" -ForegroundColor DarkGray
    Write-Host "   [C] Configure LIN1 (SSH + dev tools + SMB mount)" -ForegroundColor White
    Write-Host "   [N] Install Ansible (control node on LIN1)" -ForegroundColor White
    Write-Host "" 
    Write-Host "  DESTRUCTIVE" -ForegroundColor DarkRed
    Write-Host "   [K] One-Button Reset + Rebuild (requires 'REBUILD' confirmation)" -ForegroundColor Red
    Write-Host "   [X] Blow Away Lab (requires 'BLOW-IT-AWAY' confirmation)" -ForegroundColor Red
    Write-Host ""
    Write-Host "   [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-InteractiveMenu {
    do {
        Show-Menu
        $choice = (Read-Host "  Select").Trim().ToUpperInvariant()
        switch ($choice) {
            'A' { Invoke-MenuCommand -Name 'one-button-setup' -Command { Invoke-OneButtonSetup } }
            'B' { Invoke-MenuCommand -Name 'bootstrap' -Command { $bootstrapArgs = Get-BootstrapArgs; Invoke-RepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs } }
            'D' { Invoke-MenuCommand -Name 'deploy' -Command { $deployArgs = Get-DeployArgs; Invoke-RepoScript -BaseName 'Deploy' -Arguments $deployArgs } }
            'H' { Invoke-MenuCommand -Name 'health' -Command { $healthArgs = Get-HealthArgs; Invoke-RepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs } }
            '1' { Invoke-MenuCommand -Name 'start' -Command { Invoke-RepoScript -BaseName 'Start-LabDay' } }
            '2' { Invoke-MenuCommand -Name 'status' -Command { Invoke-RepoScript -BaseName 'Lab-Status' } }
            '3' { Invoke-MenuCommand -Name 'terminal' -Command { Invoke-RepoScript -BaseName 'Open-LabTerminal' } }
            '4' { Invoke-MenuCommand -Name 'new-project' -Command { Invoke-RepoScript -BaseName 'New-LabProject' } }
            '5' { Invoke-MenuCommand -Name 'push' -Command { Invoke-RepoScript -BaseName 'Push-ToWS1' } }
            '6' { Invoke-MenuCommand -Name 'test' -Command { Invoke-RepoScript -BaseName 'Test-OnWS1' } }
            '7' { Invoke-MenuCommand -Name 'save' -Command { Invoke-RepoScript -BaseName 'Save-LabWork' } }
            '8' {
                Invoke-MenuCommand -Name 'stop' -Command {
                    Stop-LabVMsSafe
                    Write-LabStatus -Status OK -Message "Stop requested for all lab VMs"
                }
            }
            '9' {
                Invoke-MenuCommand -Name 'rollback' -Command {
                    Ensure-LabImported
                    if (-not (Test-LabReadySnapshot)) {
                        Write-LabStatus -Status WARN -Message "LabReady snapshot not found on one or more VMs."
                        Write-Host "  Re-run deploy to recreate baseline." -ForegroundColor Yellow
                        return
                    }
                    Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                    Write-LabStatus -Status OK -Message "Restored to LabReady"
                }
            }
            'L' { Invoke-MenuCommand -Name 'add-lin1' -Command { Invoke-RepoScript -BaseName 'Add-LIN1' -Arguments @('-NonInteractive') } }
            'C' { Invoke-MenuCommand -Name 'lin1-config' -Command { Invoke-RepoScript -BaseName 'Configure-LIN1' } }
            'N' { Invoke-MenuCommand -Name 'ansible' -Command { Invoke-RepoScript -BaseName 'Install-Ansible' -Arguments @('-NonInteractive') } }
            'X' {
                Invoke-MenuCommand -Name 'blow-away' -Command {
                    $dropNet = (Read-Host "  Also remove switch/NAT? (y/n)").Trim().ToLowerInvariant() -eq 'y'
                    Invoke-BlowAway -DropNetwork:$dropNet
                }
            }
            'K' {
                Invoke-MenuCommand -Name 'one-button-reset' -Command {
                    $confirm = (Read-Host "  Type REBUILD to confirm reset+rebuild").Trim()
                    if ($confirm -eq 'REBUILD') {
                        $dropNet = (Read-Host "  Also remove switch/NAT? (y/n)").Trim().ToLowerInvariant() -eq 'y'
                        Invoke-OneButtonReset -DropNetwork:$dropNet
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
}

$runSuccess = $false
$runError = ''

try {
    Add-RunEvent -Step 'run' -Status 'start' -Message "Action=$Action"
    switch ($Action) {
        'menu' {
            if ($NonInteractive) {
                throw "Action 'menu' is interactive-only. Use an explicit noninteractive action."
            }
            Invoke-InteractiveMenu
        }
        'setup' { Invoke-Setup }
        'one-button-setup' { Invoke-OneButtonSetup }
        'one-button-reset' { Invoke-OneButtonReset -DropNetwork:$RemoveNetwork }
        'preflight' {
            $preflightArgs = Get-PreflightArgs
            Invoke-RepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs
        }
        'bootstrap' {
            $bootstrapArgs = Get-BootstrapArgs
            Invoke-RepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs
        }
        'deploy' {
            $deployArgs = Get-DeployArgs
            Invoke-RepoScript -BaseName 'Deploy' -Arguments $deployArgs
        }
        'add-lin1' {
            $linArgs = @('-NonInteractive')
            Invoke-RepoScript -BaseName 'Add-LIN1' -Arguments $linArgs
        }
        'lin1-config' {
            $linArgs = @()
            if ($NonInteractive) { $linArgs += '-NonInteractive' }
            Invoke-RepoScript -BaseName 'Configure-LIN1' -Arguments $linArgs
        }
        'ansible' {
            Invoke-RepoScript -BaseName 'Install-Ansible' -Arguments @('-NonInteractive')
        }
        'health' {
            $healthArgs = Get-HealthArgs
            Invoke-RepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs
        }

        'start' { Invoke-RepoScript -BaseName 'Start-LabDay' }
        'status' { Invoke-RepoScript -BaseName 'Lab-Status' }
        'terminal' { Invoke-RepoScript -BaseName 'Open-LabTerminal' }
        'new-project' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart', '-Force') }
            Invoke-RepoScript -BaseName 'New-LabProject' -Arguments $scriptArgs
        }
        'push' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart', '-Force') }
            Invoke-RepoScript -BaseName 'Push-ToWS1' -Arguments $scriptArgs
        }
        'test' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart') }
            Invoke-RepoScript -BaseName 'Test-OnWS1' -Arguments $scriptArgs
        }
        'save' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart') }
            Invoke-RepoScript -BaseName 'Save-LabWork' -Arguments $scriptArgs
        }
        'stop' {
            Add-RunEvent -Step 'stop' -Status 'start' -Message 'Stop-LabVMsSafe'
            Stop-LabVMsSafe
            Add-RunEvent -Step 'stop' -Status 'ok' -Message 'requested'
            Write-LabStatus -Status OK -Message "Stop requested for all lab VMs" -Indent 0
        }
        'rollback' {
            Add-RunEvent -Step 'rollback' -Status 'start' -Message 'Restore-LabVMSnapshot LabReady'
            Ensure-LabImported
            if (-not (Test-LabReadySnapshot)) {
                throw "LabReady snapshot not found on one or more VMs. Re-run deploy to recreate baseline."
            }
            Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
            Add-RunEvent -Step 'rollback' -Status 'ok' -Message 'LabReady restored'
            Write-LabStatus -Status OK -Message "Restored to LabReady" -Indent 0
        }
        'blow-away' { Invoke-BlowAway -BypassPrompt:($Force -or $NonInteractive) -DropNetwork:$RemoveNetwork -Simulate:$DryRun }
    }
    $runSuccess = $true
    Add-RunEvent -Step 'run' -Status 'ok' -Message 'completed'
} catch {
    $runError = $_.Exception.Message
    Add-RunEvent -Step 'run' -Status 'fail' -Message $runError
    throw
} finally {
    Write-RunArtifacts -Success:$runSuccess -ErrorMessage $runError
    Invoke-LogRetention
}
