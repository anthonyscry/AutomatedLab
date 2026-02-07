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
        'install-shortcuts',
        'preflight',
        'bootstrap',
        'deploy',
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
    [string]$DefaultsFile,
    [switch]$DryRun,
    [int]$LogRetentionDays = 14
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LabName = 'OpenCodeLab'
$LabVMs = @('DC1', 'WS1', 'LIN1')
$LabPath = 'C:\AutomatedLab\OpenCodeLab'
$SwitchName = 'OpenCodeLabSwitch'
$NatName = 'OpenCodeLabSwitchNAT'
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
        "success: $Success",
        "started_utc: $($RunStart.ToUniversalTime().ToString('o'))",
        "ended_utc: $($ended.ToUniversalTime().ToString('o'))",
        "duration_seconds: $duration",
        "error: $ErrorMessage",
        "host: $env:COMPUTERNAME",
        "user: $env:USERDOMAIN\$env:USERNAME",
        "events:"
    )

    foreach ($event in $RunEvents) {
        $lines += "- [$($event.Time)] $($event.Step) :: $($event.Status) :: $($event.Message)"
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
    try {
        Ensure-LabImported
        foreach ($vmName in $LabVMs) {
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
}

function Resolve-ScriptPath {
    param([Parameter(Mandatory)][string]$BaseName)
    $path = Join-Path $ScriptDir "$BaseName.ps1"
    if (-not (Test-Path $path)) {
        throw "Script not found: $path"
    }
    return $path
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
            & $path @Arguments
        } else {
            & $path
        }
        Add-RunEvent -Step $BaseName -Status 'ok' -Message 'completed'
    } catch {
        Add-RunEvent -Step $BaseName -Status 'fail' -Message $_.Exception.Message
        throw
    }
}

function Ensure-LabImported {
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
        Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  [WARN] Remove-Lab returned: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "  [3/5] Removing Hyper-V VMs/checkpoints if present..." -ForegroundColor Cyan
    foreach ($vmName in $LabVMs) {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm) {
            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            Write-Host "    removed VM $vmName" -ForegroundColor Gray
        }
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

    Write-Host "`n  [OK] Lab teardown complete." -ForegroundColor Green
    Write-Host "  Run '.\OpenCodeLab-App.ps1 -Action setup' to rebuild." -ForegroundColor Gray
}

function Invoke-OneButtonSetup {
    Write-Host "`n=== ONE-BUTTON SETUP ===" -ForegroundColor Cyan
    Write-Host "  Bootstrapping prerequisites + deploying lab + start + status" -ForegroundColor Gray

    $bootstrapArgs = @()
    if ($NonInteractive) { $bootstrapArgs += '-NonInteractive' }

    Invoke-RepoScript -BaseName 'Test-OpenCodeLabPreflight'
    Invoke-RepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs

    # Verify VMs exist after bootstrap (bootstrap chains into deploy)
    $missingVMs = $LabVMs | Where-Object { -not (Hyper-V\Get-VM -Name $_ -ErrorAction SilentlyContinue) }
    if ($missingVMs) {
        throw "VMs not found after bootstrap: $($missingVMs -join ', '). Deploy may have failed."
    }

    Invoke-RepoScript -BaseName 'Start-LabDay'
    Invoke-RepoScript -BaseName 'Lab-Status'

    try {
        Invoke-RepoScript -BaseName 'Test-OpenCodeLabHealth'
        Write-Host "  [OK] Post-deploy health gate passed" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] Post-deploy health gate failed" -ForegroundColor Red
        Write-Host "  Attempting automatic rollback to LabReady..." -ForegroundColor Yellow
        try {
            Ensure-LabImported
            if (-not (Test-LabReadySnapshot)) {
                Add-RunEvent -Step 'rollback' -Status 'fail' -Message 'LabReady snapshot missing'
                Write-Host "  [WARN] LabReady snapshot missing. Cannot auto-rollback." -ForegroundColor Yellow
                Write-Host "  Run deploy once to recreate LabReady checkpoint." -ForegroundColor Yellow
            } else {
                Add-RunEvent -Step 'rollback' -Status 'start' -Message 'Restore-LabVMSnapshot LabReady'
                Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                Add-RunEvent -Step 'rollback' -Status 'ok' -Message 'LabReady restored'
                Write-Host "  [OK] Automatic rollback completed" -ForegroundColor Green
                Invoke-RepoScript -BaseName 'Lab-Status'
            }
        } catch {
            Add-RunEvent -Step 'rollback' -Status 'fail' -Message $_.Exception.Message
            Write-Host "  [WARN] Automatic rollback failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        throw
    }

    Write-Host "`n  [OK] One-button setup complete." -ForegroundColor Green
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
    $bootstrapArgs = @()
    if ($NonInteractive) { $bootstrapArgs += '-NonInteractive' }

    Invoke-RepoScript -BaseName 'Test-OpenCodeLabPreflight'
    Invoke-RepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs
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
    Write-Host "   [A] One-Button Setup (bootstrap + deploy + start + status)" -ForegroundColor Green
    Write-Host "   [B] Bootstrap + Deploy" -ForegroundColor White
    Write-Host "   [D] Deploy only" -ForegroundColor White
    Write-Host "   [I] Install Desktop Shortcuts" -ForegroundColor White
    Write-Host ""
    Write-Host "  DAILY" -ForegroundColor DarkCyan
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
    Write-Host "  DESTRUCTIVE" -ForegroundColor DarkRed
    Write-Host "   [K] One-Button Reset/Rebuild" -ForegroundColor Red
    Write-Host "   [X] Blow Away Lab" -ForegroundColor Red
    Write-Host ""
    Write-Host "   [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-InteractiveMenu {
    do {
        Show-Menu
        $choice = (Read-Host "  Select").ToUpperInvariant()
        switch ($choice) {
            'A' { Invoke-OneButtonSetup; Read-Host "`n  Press Enter to continue" | Out-Null }
            'B' { Invoke-RepoScript -BaseName 'Bootstrap'; Read-Host "`n  Press Enter to continue" | Out-Null }
            'D' { Invoke-RepoScript -BaseName 'Deploy'; Read-Host "`n  Press Enter to continue" | Out-Null }
            'I' { Invoke-RepoScript -BaseName 'Create-DesktopShortcuts'; Read-Host "`n  Press Enter to continue" | Out-Null }
            'H' { Invoke-RepoScript -BaseName 'Test-OpenCodeLabHealth'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '1' { Invoke-RepoScript -BaseName 'Start-LabDay'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '2' { Invoke-RepoScript -BaseName 'Lab-Status'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '3' { Invoke-RepoScript -BaseName 'Open-LabTerminal'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '4' { Invoke-RepoScript -BaseName 'New-LabProject'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '5' { Invoke-RepoScript -BaseName 'Push-ToWS1'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '6' { Invoke-RepoScript -BaseName 'Test-OnWS1'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '7' { Invoke-RepoScript -BaseName 'Save-LabWork'; Read-Host "`n  Press Enter to continue" | Out-Null }
            '8' {
                Stop-LabVMsSafe
                Write-Host "  [OK] Stop requested for all lab VMs" -ForegroundColor Green
                Read-Host "`n  Press Enter to continue" | Out-Null
            }
            '9' {
                Ensure-LabImported
                if (-not (Test-LabReadySnapshot)) {
                    Write-Host "  [WARN] LabReady snapshot not found on one or more VMs." -ForegroundColor Yellow
                    Write-Host "  Re-run deploy to recreate baseline." -ForegroundColor Yellow
                    Read-Host "`n  Press Enter to continue" | Out-Null
                    break
                }
                Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                Write-Host "  [OK] Restored to LabReady" -ForegroundColor Green
                Read-Host "`n  Press Enter to continue" | Out-Null
            }
            'X' {
                $dropNet = (Read-Host "  Also remove switch/NAT? (y/n)").ToLowerInvariant() -eq 'y'
                Invoke-BlowAway -DropNetwork:$dropNet
                Read-Host "`n  Press Enter to continue" | Out-Null
            }
            'K' {
                $confirm = Read-Host "  Type REBUILD to confirm reset+rebuild"
                if ($confirm -eq 'REBUILD') {
                    $dropNet = (Read-Host "  Also remove switch/NAT? (y/n)").ToLowerInvariant() -eq 'y'
                    Invoke-OneButtonReset -DropNetwork:$dropNet
                } else {
                    Write-Host "  [ABORT] Cancelled" -ForegroundColor Yellow
                }
                Read-Host "`n  Press Enter to continue" | Out-Null
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
        'install-shortcuts' { Invoke-RepoScript -BaseName 'Create-DesktopShortcuts' }
        'preflight' { Invoke-RepoScript -BaseName 'Test-OpenCodeLabPreflight' }
        'bootstrap' {
            $bootstrapArgs = @()
            if ($NonInteractive) { $bootstrapArgs += '-NonInteractive' }
            Invoke-RepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs
        }
        'deploy' {
            $deployArgs = @()
            if ($NonInteractive) { $deployArgs += '-NonInteractive' }
            Invoke-RepoScript -BaseName 'Deploy' -Arguments $deployArgs
        }
        'health' { Invoke-RepoScript -BaseName 'Test-OpenCodeLabHealth' }
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
            Write-Host "[OK] Stop requested for all lab VMs" -ForegroundColor Green
        }
        'rollback' {
            Add-RunEvent -Step 'rollback' -Status 'start' -Message 'Restore-LabVMSnapshot LabReady'
            Ensure-LabImported
            if (-not (Test-LabReadySnapshot)) {
                throw "LabReady snapshot not found on one or more VMs. Re-run deploy to recreate baseline."
            }
            Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
            Add-RunEvent -Step 'rollback' -Status 'ok' -Message 'LabReady restored'
            Write-Host "[OK] Restored to LabReady" -ForegroundColor Green
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
