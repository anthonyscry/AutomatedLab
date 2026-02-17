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
        'asset-report',
        'offline-bundle',
        'terminal',
        'new-project',
        'push',
        'test',
        'save',
        'stop',
        'rollback',
        'blow-away',
        'teardown'
    )]
    [string]$Action = 'menu',
    [ValidateSet('quick', 'full')]
    [string]$Mode = 'full',
    [string[]]$TargetHosts,
    [string]$InventoryPath,
    [string]$ConfirmationToken,
    [string]$ProfilePath,
    [switch]$Force,
    [switch]$RemoveNetwork,
    [switch]$NonInteractive,
    [switch]$AutoFixSubnetConflict,
    [switch]$AutoHeal = $true,
    [switch]$CoreOnly = $true,
    [string]$DefaultsFile,
    [switch]$DryRun,
    [switch]$NoExecute,
    [string]$NoExecuteStateJson,
    [string]$NoExecuteStatePath,
    [ValidateSet('off', 'canary', 'enforced')]
    [string]$DispatchMode,
    [int]$LogRetentionDays = 14
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$SkipRuntimeBootstrap = -not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_SKIP_RUNTIME_BOOTSTRAP)
if ((-not $NoExecute) -and (-not $SkipRuntimeBootstrap)) {
    if (-not (Test-Path $ConfigPath)) {
        throw "Required configuration not found: $ConfigPath"
    }
    . $ConfigPath
}

$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if ((-not $NoExecute) -and (-not $SkipRuntimeBootstrap)) {
    if (-not (Test-Path $CommonPath)) {
        throw "Required helper loader not found: $CommonPath"
    }
    . $CommonPath
}

# When bootstrap is skipped (test mode or NoExecute), create minimal config and load required helpers
if ($SkipRuntimeBootstrap -or $NoExecute) {
    $script:GlobalLabConfig = @{
        Lab = @{
            Name = 'TestLab'
            CoreVMNames = @('dc1', 'svr1', 'ws1')
            DomainName = 'test.local'
            TimeZone = 'Pacific Standard Time'
        }
        Paths = @{
            LabRoot = 'C:\TestLabRoot'
            LabSourcesRoot = 'C:\TestLabSources'
        }
        Network = @{
            SwitchName = 'TestSwitch'
            NatName = 'TestNat'
            AddressSpace = '172.16.0.0/24'
        }
        VMSizing = @{
            Server = @{ Memory = 2GB; Processors = 2 }
            Client = @{ Memory = 2GB; Processors = 2 }
        }
        AutoHeal = @{
            Enabled = $true
            TimeoutSeconds = 60
            HealthCheckTimeoutSeconds = 10
        }
    }

    # Load all Private/ helpers (same as Lab-Common.ps1)
    $importHelperPath = Join-Path $ScriptDir 'Private/Import-LabScriptTree.ps1'
    if (Test-Path $importHelperPath) {
        . $importHelperPath
        $privateFiles = Get-LabScriptFiles -RootPath $ScriptDir -RelativePaths @('Private') -ExcludeFileNames @('Import-LabScriptTree.ps1')
        foreach ($file in $privateFiles) {
            . $file.FullName
        }
    }
}

# Alias for backward compatibility with existing code
Set-Alias -Name Remove-VMHardSafe -Value Remove-HyperVVMStale -Scope Script

if ($SkipRuntimeBootstrap -or $NoExecute) {
    $SwitchName = 'TestSwitch'
}
else {
    $SwitchName = $GlobalLabConfig.Network.SwitchName
}
$RunStart = Get-Date
$RunId = (Get-Date -Format 'yyyyMMdd-HHmmss')
$RunLogRoot = if ([string]::IsNullOrWhiteSpace($env:OPENCODELAB_RUN_LOG_ROOT)) { 'C:\LabSources\Logs' } else { [string]$env:OPENCODELAB_RUN_LOG_ROOT }
$WriteArtifactsInNoExecute = -not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_WRITE_ARTIFACTS_IN_NOEXECUTE)
$RunEvents = New-Object System.Collections.Generic.List[object]
$RequestedMode = $Mode
$EffectiveMode = $Mode
$FallbackReason = $null
$ProfileSource = if ([string]::IsNullOrWhiteSpace($ProfilePath)) { 'default' } else { 'file' }
$ResolvedDispatchMode = 'off'

if (Get-Command Resolve-LabDispatchMode -ErrorAction SilentlyContinue) {
    if ($PSBoundParameters.ContainsKey('DispatchMode')) {
        $resolvedDispatchModeResult = Resolve-LabDispatchMode -Mode $DispatchMode
    }
    else {
        $resolvedDispatchModeResult = Resolve-LabDispatchMode
    }
    $ResolvedDispatchMode = [string]$resolvedDispatchModeResult.Mode
}
elseif ($PSBoundParameters.ContainsKey('DispatchMode')) {
    $ResolvedDispatchMode = [string]$DispatchMode
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
        dispatch_mode = $ResolvedDispatchMode
        execution_outcome = $executionOutcome
        execution_started_at = $executionStartedAt
        execution_completed_at = $executionCompletedAt
        requested_mode = $RequestedMode
        effective_mode = $EffectiveMode
        fallback_reason = $FallbackReason
        profile_source = $ProfileSource
        noninteractive = [bool]$NonInteractive
        core_only = [bool]$CoreOnly
        force = [bool]$Force
        remove_network = [bool]$RemoveNetwork
        dry_run = [bool]$DryRun
        auto_heal = if ((Test-Path variable:healResult) -and $null -ne $healResult) { $healResult } else { $null }
        defaults_file = $DefaultsFile
        started_utc = $RunStart.ToUniversalTime().ToString('o')
        ended_utc = $ended.ToUniversalTime().ToString('o')
        duration_seconds = $duration
        success = $Success
        error = $ErrorMessage
        policy_outcome = $policyOutcome
        policy_reason = $policyReason
        host_outcomes = @($hostOutcomes)
        blast_radius = @($blastRadius)
        host = $env:COMPUTERNAME
        user = "$env:USERDOMAIN\$env:USERNAME"
        events = $RunEvents
    }

    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    $lines = @(
        "run_id: $RunId",
        "action: $Action",
        "dispatch_mode: $ResolvedDispatchMode",
        "execution_outcome: $executionOutcome",
        "execution_started_at: $executionStartedAt",
        "execution_completed_at: $executionCompletedAt",
        "requested_mode: $RequestedMode",
        "effective_mode: $EffectiveMode",
        "fallback_reason: $FallbackReason",
        "profile_source: $ProfileSource",
        "core_only: $CoreOnly",
        "success: $Success",
        "started_utc: $($RunStart.ToUniversalTime().ToString('o'))",
        "ended_utc: $($ended.ToUniversalTime().ToString('o'))",
        "duration_seconds: $duration",
        "error: $ErrorMessage",
        "policy_outcome: $policyOutcome",
        "policy_reason: $policyReason",
        "host_outcomes: $((@($hostOutcomes | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'HostName') { [string]$_.HostName } else { 'unknown' } }) -join ','))",
        "blast_radius: $($blastRadius -join ',')",
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
        } else {
            $targets = @(Get-LabExpectedVMs -LabConfig $GlobalLabConfig)
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
    if ($null -ne $defaults.AutoFixSubnetConflict) { $AutoFixSubnetConflict = [bool]$defaults.AutoFixSubnetConflict }
    if ($null -ne $defaults.CoreOnly) { $CoreOnly = [bool]$defaults.CoreOnly }
}

function Invoke-OrchestrationActionCore {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('deploy', 'teardown')]
        [string]$OrchestrationAction,

        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$Mode,

        [Parameter(Mandatory)]
        [object]$Intent
    )

    switch ($OrchestrationAction) {
        'deploy' {
            if ($Intent.RunQuickStartupSequence) {
                Invoke-QuickDeploy
            }
            else {
                $deployArgs = Get-LabDeployArgs -Mode $Mode -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict
                Invoke-LabRepoScript -BaseName 'Deploy' -Arguments $deployArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
            }
        }
        'teardown' {
            if ($Intent.RunQuickReset) {
                Invoke-QuickTeardown
            }
            else {
                Invoke-BlowAway -BypassPrompt:($Force -or $NonInteractive) -DropNetwork:$RemoveNetwork -Simulate:$DryRun
            }
        }
    }
}

function Resolve-NoExecuteStateOverride {
    if (-not $NoExecute) {
        return $null
    }

    $state = $null

    if (-not [string]::IsNullOrWhiteSpace($NoExecuteStateJson)) {
        $state = ($NoExecuteStateJson | ConvertFrom-Json)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($NoExecuteStatePath)) {
        if (-not (Test-Path $NoExecuteStatePath)) {
            throw "NoExecute state path not found: $NoExecuteStatePath"
        }

        $state = (Get-Content -Raw -Path $NoExecuteStatePath | ConvertFrom-Json)
    }

    if ($null -eq $state) {
        return $null
    }

    if ($state -is [System.Array]) {
        return @($state)
    }

    if ($state -is [System.Collections.IEnumerable] -and $state -isnot [string] -and $state.PSObject.TypeNames -contains 'System.Object[]') {
        return @($state)
    }

    $statePropertyNames = @($state.PSObject.Properties.Name)
    if (($statePropertyNames -contains 'Reachable') -or ($statePropertyNames -contains 'HostName')) {
        return @($state)
    }

    if ($statePropertyNames -contains 'HostProbes') {
        return @($state.HostProbes)
    }

    if ($statePropertyNames -contains 'MissingVMs') {
        $state.MissingVMs = @($state.MissingVMs)
    }
    else {
        $state | Add-Member -NotePropertyName 'MissingVMs' -NotePropertyValue @()
    }

    return $state
}

function Resolve-RuntimeStateOverride {
    if (-not $SkipRuntimeBootstrap) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($env:OPENCODELAB_RUNTIME_STATE_JSON)) {
        return $null
    }

    $state = $null
    try {
        $state = ($env:OPENCODELAB_RUNTIME_STATE_JSON | ConvertFrom-Json)
    }
    catch {
        throw "Runtime state override JSON is invalid."
    }

    if ($null -eq $state) {
        return $null
    }

    if ($state -is [System.Array]) {
        return @($state)
    }

    if ($state -is [System.Collections.IEnumerable] -and $state -isnot [string] -and $state.PSObject.TypeNames -contains 'System.Object[]') {
        return @($state)
    }

    $statePropertyNames = @($state.PSObject.Properties.Name)
    if (($statePropertyNames -contains 'Reachable') -or ($statePropertyNames -contains 'HostName')) {
        return @($state)
    }

    if ($statePropertyNames -contains 'HostProbes') {
        return @($state.HostProbes)
    }

    if ($statePropertyNames -contains 'MissingVMs') {
        $state.MissingVMs = @($state.MissingVMs)
    }
    else {
        $state | Add-Member -NotePropertyName 'MissingVMs' -NotePropertyValue @()
    }

    return $state
}

function Ensure-LabImported {
    if (Get-Module -Name AutomatedLab -ErrorAction SilentlyContinue) {
        # Module already loaded; just ensure lab is imported
        try {
            $lab = Get-Lab -ErrorAction SilentlyContinue
            if ($lab -and $lab.Name -eq $GlobalLabConfig.Lab.Name) { return }
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
        Import-Lab -Name $GlobalLabConfig.Lab.Name -ErrorAction Stop | Out-Null
    } catch {
        throw "Lab '$($GlobalLabConfig.Lab.Name)' is not registered. Run setup first."
    }
}

function Stop-LabVMsSafe {
    try {
        Ensure-LabImported
        Stop-LabVM -All -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Get-VM -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @($GlobalLabConfig.Lab.CoreVMNames) -and $_.State -eq 'Running' } |
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
        Write-Host "  Would stop lab VMs: $(@($GlobalLabConfig.Lab.CoreVMNames) -join ', ')" -ForegroundColor DarkGray
        Write-Host "  Would remove lab definition: $($GlobalLabConfig.Lab.Name)" -ForegroundColor DarkGray
        Write-Host "  Would remove lab files: $(Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name)" -ForegroundColor DarkGray
        Write-Host "  Would clear SSH known_hosts entries" -ForegroundColor DarkGray
        if ($DropNetwork) {
            Write-Host "  Would remove network: $SwitchName / $($GlobalLabConfig.Network.NatName)" -ForegroundColor DarkGray
        }
        Add-LabRunEvent -Step 'blow-away' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
        return
    }

    Write-Host "`n=== BLOW AWAY LAB ===" -ForegroundColor Red
    Write-Host "  This will stop VMs, remove lab definition, and delete local lab files." -ForegroundColor Yellow
    if ($DropNetwork) {
        Write-Host "  Network objects ($SwitchName / $($GlobalLabConfig.Network.NatName)) will also be removed." -ForegroundColor Yellow
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
        Remove-Lab -Name $GlobalLabConfig.Lab.Name -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 2>$null
    } catch {
        Write-LabStatus -Status WARN -Message "Remove-Lab returned: $($_.Exception.Message)"
    }

    Write-Host "  [3/5] Removing Hyper-V VMs/checkpoints if present..." -ForegroundColor Cyan
    $allLabVMs = @(@($GlobalLabConfig.Lab.CoreVMNames)) + @('LIN1')
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
    if (Test-Path (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name)) {
        Remove-Item -Path (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name) -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    removed $(Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name)" -ForegroundColor Gray
    }

    Write-Host "  [4b/5] Clearing SSH known hosts..." -ForegroundColor Cyan
    if (Get-Command Clear-LabSSHKnownHosts -ErrorAction SilentlyContinue) {
        try {
            Clear-LabSSHKnownHosts
            Write-Host "    SSH known_hosts cleared" -ForegroundColor Gray
        } catch {
            Write-LabStatus -Status WARN -Message "SSH known_hosts cleanup failed: $($_.Exception.Message)"
        }
    }

    Write-Host "  [5/5] Cleaning network artifacts (optional)..." -ForegroundColor Cyan
    if ($DropNetwork) {
        $nat = Get-NetNat -Name $GlobalLabConfig.Network.NatName -ErrorAction SilentlyContinue
        if ($nat) {
            Remove-NetNat -Name $GlobalLabConfig.Network.NatName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "    removed NAT $($GlobalLabConfig.Network.NatName)" -ForegroundColor Gray

            # Verify NAT removal
            $natCheck = Get-NetNat -Name $GlobalLabConfig.Network.NatName -ErrorAction SilentlyContinue
            if ($natCheck) {
                Write-LabStatus -Status WARN -Message "NAT '$($GlobalLabConfig.Network.NatName)' still present after removal attempt"
            }
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
    Write-Host "  Mode: WINDOWS CORE (DC1 + SVR1 + WS1)" -ForegroundColor Green
    Write-Host "  Bootstrapping prerequisites + deploying lab + start + status" -ForegroundColor Gray

    $preflightArgs = Get-LabPreflightArgs
    $bootstrapArgs = Get-LabBootstrapArgs -Mode $EffectiveMode -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict

    Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
    Invoke-LabRepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs -ScriptDir $ScriptDir -RunEvents $RunEvents

    # Verify expected VMs exist after bootstrap (bootstrap chains into deploy)
    $expectedVMs = Get-LabExpectedVMs -LabConfig $GlobalLabConfig
    $missingVMs = $expectedVMs | Where-Object { -not (Hyper-V\Get-VM -Name $_ -ErrorAction SilentlyContinue) }
    if ($missingVMs) {
        throw "VMs not found after bootstrap: $($missingVMs -join ', '). Deploy may have failed."
    }

    Invoke-LabRepoScript -BaseName 'Start-LabDay' -ScriptDir $ScriptDir -RunEvents $RunEvents
    Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents

    $healthArgs = Get-LabHealthArgs
    try {
        Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        Write-LabStatus -Status OK -Message "Post-deploy health gate passed"
    } catch {
        Write-LabStatus -Status FAIL -Message "Post-deploy health gate failed"
        Write-Host "  Attempting automatic rollback to LabReady..." -ForegroundColor Yellow
        try {
            Ensure-LabImported
            if (-not (Test-LabReadySnapshot)) {
                Add-LabRunEvent -Step 'rollback' -Status 'fail' -Message 'LabReady snapshot missing' -RunEvents $RunEvents
                Write-LabStatus -Status WARN -Message "LabReady snapshot missing. Cannot auto-rollback."
                Write-Host "  Run deploy once to recreate LabReady checkpoint." -ForegroundColor Yellow
            } else {
                Add-LabRunEvent -Step 'rollback' -Status 'start' -Message 'Restore-LabVMSnapshot LabReady' -RunEvents $RunEvents
                Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                Add-LabRunEvent -Step 'rollback' -Status 'ok' -Message 'LabReady restored' -RunEvents $RunEvents
                Write-LabStatus -Status OK -Message "Automatic rollback completed"
                Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents
            }
        } catch {
            Add-LabRunEvent -Step 'rollback' -Status 'fail' -Message $_.Exception.Message -RunEvents $RunEvents
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
        Add-LabRunEvent -Step 'one-button-reset' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
        return
    }

    # For direct action calls (not from menu), require confirmation unless Force/NonInteractive
    $shouldBypassPrompt = $Force -or $NonInteractive
    Invoke-BlowAway -BypassPrompt:$shouldBypassPrompt -DropNetwork:$DropNetwork
    Invoke-OneButtonSetup
}

function Invoke-Setup {
    $preflightArgs = Get-LabPreflightArgs
    $bootstrapArgs = Get-LabBootstrapArgs -Mode $EffectiveMode -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict

    Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
    Invoke-LabRepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
}

function Invoke-QuickDeploy {
    if ($DryRun) {
        Write-Host "`n=== DRY RUN: QUICK DEPLOY ===" -ForegroundColor Yellow
        Write-Host '  Would run quick startup sequence: Start-LabDay -> Lab-Status -> Test-OpenCodeLabHealth' -ForegroundColor DarkGray
        Add-LabRunEvent -Step 'deploy-quick' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
        return
    }

    Write-Host "`n=== QUICK DEPLOY ===" -ForegroundColor Cyan
    Invoke-LabRepoScript -BaseName 'Start-LabDay' -ScriptDir $ScriptDir -RunEvents $RunEvents
    Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents
    $healthArgs = Get-LabHealthArgs
    Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
}

function Invoke-QuickTeardown {
    if ($DryRun) {
        Write-Host "`n=== DRY RUN: QUICK TEARDOWN ===" -ForegroundColor Yellow
        Write-Host '  Would stop VMs and restore LabReady snapshot when available' -ForegroundColor DarkGray
        Add-LabRunEvent -Step 'teardown-quick' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
        return
    }

    Write-Host "`n=== QUICK TEARDOWN ===" -ForegroundColor Cyan
    Add-LabRunEvent -Step 'teardown-quick' -Status 'start' -Message 'stop + optional restore' -RunEvents $RunEvents
    Stop-LabVMsSafe

    try {
        Ensure-LabImported
        if (Test-LabReadySnapshot -VMNames (Get-LabExpectedVMs -LabConfig $GlobalLabConfig)) {
            Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
            Add-LabRunEvent -Step 'teardown-quick' -Status 'ok' -Message 'LabReady restored' -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message 'Quick teardown complete (LabReady restored)' -Indent 0
        }
        else {
            Add-LabRunEvent -Step 'teardown-quick' -Status 'warn' -Message 'LabReady not found; VMs stopped only' -RunEvents $RunEvents
            Write-LabStatus -Status WARN -Message 'LabReady snapshot missing; quick teardown stopped VMs only.' -Indent 0
        }
    }
    catch {
        Add-LabRunEvent -Step 'teardown-quick' -Status 'fail' -Message 'Restore skipped after stop' -RunEvents $RunEvents
        Write-LabStatus -Status WARN -Message "Quick teardown restored no snapshot: $($_.Exception.Message)" -Indent 0
    }
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

    Add-LabRunEvent -Step "menu:$Name" -Status 'start' -Message 'interactive' -RunEvents $RunEvents
    try {
        & $Command
        Add-LabRunEvent -Step "menu:$Name" -Status 'ok' -Message 'completed' -RunEvents $RunEvents
    } catch {
        Add-LabRunEvent -Step "menu:$Name" -Status 'fail' -Message $_.Exception.Message -RunEvents $RunEvents
        Write-LabStatus -Status FAIL -Message "$($_.Exception.Message)"
    }

    if (-not $NoPause) {
        Pause-Menu
    }
}

function Get-MenuVmSelection {
    param([string]$SuggestedVM = '')

    $vmNames = @()
    try {
        $vmNames = @(Hyper-V\Get-VM -ErrorAction Stop | Select-Object -ExpandProperty Name)
    } catch {
        $vmNames = @(@($GlobalLabConfig.Lab.CoreVMNames)) + @('LIN1')
    }

    $vmNames = @($vmNames | Sort-Object -Unique)
    if (-not $vmNames -or $vmNames.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($SuggestedVM)) {
            return $SuggestedVM
        }
        return (Read-Host '  Target VM name').Trim()
    }

    Write-Host ''
    Write-Host '  Available target VMs:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $vmNames.Count; $i++) {
        Write-Host ("   [{0}] {1}" -f ($i + 1), $vmNames[$i]) -ForegroundColor Gray
    }
    Write-Host '   [N] Enter custom VM name' -ForegroundColor Gray

    if (-not [string]::IsNullOrWhiteSpace($SuggestedVM)) {
        Write-Host ("  Suggested target: {0}" -f $SuggestedVM) -ForegroundColor DarkGray
    }

    $selection = (Read-Host '  Select target VM').Trim().ToUpperInvariant()
    if ($selection -eq 'N') {
        return (Read-Host '  Enter custom VM name').Trim()
    }

    $index = 0
    if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $vmNames.Count) {
        return $vmNames[$index - 1]
    }

    if (-not [string]::IsNullOrWhiteSpace($SuggestedVM)) {
        return $SuggestedVM
    }

    return $vmNames[0]
}

function Invoke-ConfigureRoleMenu {
    $roles = @(
        [pscustomobject]@{ Key = '1'; Name = 'DC';         DefaultVM = 'DC1';     BuilderTag = 'DC';         Automation = 'Built-in domain role' },
        [pscustomobject]@{ Key = '2'; Name = 'WSUS';       DefaultVM = 'WSUS1';   BuilderTag = 'WSUS';       Automation = 'LabBuilder unattended install' },
        [pscustomobject]@{ Key = '3'; Name = 'SQL';        DefaultVM = 'SQL1';    BuilderTag = 'SQL';        Automation = 'LabBuilder unattended install' },
        [pscustomobject]@{ Key = '4'; Name = 'DHCP';       DefaultVM = 'DHCP1';    BuilderTag = 'DHCP';       Automation = 'LabBuilder automated role pipeline' },
        [pscustomobject]@{ Key = '5'; Name = 'File Server';DefaultVM = 'FILE1';    BuilderTag = 'FileServer'; Automation = 'LabBuilder scaffold available' },
        [pscustomobject]@{ Key = '6'; Name = 'Print Server';DefaultVM = 'PRN1';     BuilderTag = 'PrintServer'; Automation = 'AutomatedLab Windows feature' },
        [pscustomobject]@{ Key = '7'; Name = 'Splunk';      DefaultVM = 'SPLUNK1';  BuilderTag = '';            Automation = 'Custom install required' },
        [pscustomobject]@{ Key = '8'; Name = 'Commvault';   DefaultVM = 'CV1';      BuilderTag = '';            Automation = 'Custom install required' },
        [pscustomobject]@{ Key = '9'; Name = 'Trellix';     DefaultVM = 'TRELLIX1'; BuilderTag = '';            Automation = 'Custom install required' },
        [pscustomobject]@{ Key = '0'; Name = 'ISE';         DefaultVM = 'ISE1';     BuilderTag = '';            Automation = 'Custom install required' }
    )

    Write-Host ''
    Write-Host '  CONFIGURE ROLE' -ForegroundColor Cyan
    foreach ($role in $roles) {
        Write-Host ("   [{0}] {1}" -f $role.Key, $role.Name) -ForegroundColor White
    }
    Write-Host '   [X] Back' -ForegroundColor DarkGray

    $roleChoice = (Read-Host '  Select role').Trim().ToUpperInvariant()
    if ($roleChoice -eq 'X') { return }

    $selectedRole = $roles | Where-Object { $_.Key -eq $roleChoice } | Select-Object -First 1
    if (-not $selectedRole) {
        Write-Host '  Invalid role selection.' -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  Role topology mode:' -ForegroundColor Cyan
    Write-Host '   [P] Primary (default)' -ForegroundColor Gray
    Write-Host '   [S] Secondary' -ForegroundColor Gray
    $modeChoice = (Read-Host '  Select mode').Trim().ToUpperInvariant()
    $roleMode = if ($modeChoice -eq 'S') { 'Secondary' } else { 'Primary' }

    $targetVM = Get-MenuVmSelection -SuggestedVM $selectedRole.DefaultVM
    if ([string]::IsNullOrWhiteSpace($targetVM)) {
        Write-Host '  Target VM is required.' -ForegroundColor Red
        return
    }

    Add-LabRunEvent -Step 'configure-role' -Status 'ok' -Message ("Role={0}; Mode={1}; Target={2}" -f $selectedRole.Name, $roleMode, $targetVM) -RunEvents $RunEvents

    Write-Host ''
    Write-LabStatus -Status OK -Message ("Role plan captured: {0} ({1}) on {2}" -f $selectedRole.Name, $roleMode, $targetVM)
    Write-Host ("  Automation: {0}" -f $selectedRole.Automation) -ForegroundColor DarkGray

    if (-not [string]::IsNullOrWhiteSpace($selectedRole.BuilderTag)) {
        $builderPath = Join-Path $ScriptDir 'LabBuilder\Invoke-LabBuilder.ps1'
        Write-Host '  AutomatedLab-backed role detected.' -ForegroundColor Green
        Write-Host ("  Build command: {0} -Operation Build -Roles DC,{1}" -f $builderPath, $selectedRole.BuilderTag) -ForegroundColor Gray

        $runNow = (Read-Host '  Run this build now? (Y/n)').Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($runNow) -or $runNow -eq 'y' -or $runNow -eq 'yes') {
            if (-not (Test-Path $builderPath)) {
                Write-Host ("  LabBuilder entry not found: {0}" -f $builderPath) -ForegroundColor Red
                return
            }

            $rolesToBuild = @('DC', $selectedRole.BuilderTag) | Select-Object -Unique
            & $builderPath -Operation Build -Roles $rolesToBuild
        }
    } else {
        Write-Host '  This role does not have an automated installer in this repo yet.' -ForegroundColor Yellow
    }
}

function Invoke-AddVMWizard {
    param(
        [Parameter(Mandatory)][ValidateSet('Server', 'Workstation')][string]$VMType
    )

    $defaultName = if ($VMType -eq 'Server') { 'SVR2' } else { 'WS2' }
    $defaultMemory = if ($VMType -eq 'Server') { 4 } else { 6 }
    $defaultCpu = 2

    $vmNameInput = (Read-Host ("  VM name [{0}]" -f $defaultName)).Trim()
    $vmName = if ([string]::IsNullOrWhiteSpace($vmNameInput)) { $defaultName } else { $vmNameInput }

    $memoryInput = (Read-Host ("  Memory GB [{0}]" -f $defaultMemory)).Trim()
    $memoryGB = $defaultMemory
    if (-not [string]::IsNullOrWhiteSpace($memoryInput)) {
        $parsedMemory = 0
        if ([int]::TryParse($memoryInput, [ref]$parsedMemory) -and $parsedMemory -ge 1) {
            $memoryGB = $parsedMemory
        }
    }

    $cpuInput = (Read-Host ("  CPU count [{0}]" -f $defaultCpu)).Trim()
    $cpuCount = $defaultCpu
    if (-not [string]::IsNullOrWhiteSpace($cpuInput)) {
        $parsedCpu = 0
        if ([int]::TryParse($cpuInput, [ref]$parsedCpu) -and $parsedCpu -ge 1) {
            $cpuCount = $parsedCpu
        }
    }

    $isoPath = (Read-Host '  ISO path (optional, leave blank for none)').Trim()

    $diskRoot = Join-Path (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name) 'Disks'
    if (-not (Test-Path $diskRoot)) {
        New-Item -Path $diskRoot -ItemType Directory -Force | Out-Null
    }
    $vhdPath = Join-Path $diskRoot ("{0}.vhdx" -f $vmName)

    Write-Host ''
    Write-Host '  VM plan:' -ForegroundColor Cyan
    Write-Host ("    Type: {0}" -f $VMType) -ForegroundColor Gray
    Write-Host ("    Name: {0}" -f $vmName) -ForegroundColor Gray
    Write-Host ("    MemoryGB: {0}" -f $memoryGB) -ForegroundColor Gray
    Write-Host ("    CPU: {0}" -f $cpuCount) -ForegroundColor Gray
    Write-Host ("    Switch: {0}" -f $GlobalLabConfig.Network.SwitchName) -ForegroundColor Gray
    Write-Host ("    VHD: {0}" -f $vhdPath) -ForegroundColor Gray
    if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
        Write-Host ("    ISO: {0}" -f $isoPath) -ForegroundColor Gray
    }

    $confirm = (Read-Host '  Create VM now? (y/n)').Trim().ToLowerInvariant()
    if ($confirm -ne 'y') {
        Write-Host '  VM creation cancelled.' -ForegroundColor Yellow
        return
    }

    $newVmCmd = Get-Command New-LabVM -ErrorAction SilentlyContinue
    if (-not $newVmCmd) {
        Write-Host '  New-LabVM function is not available in this session.' -ForegroundColor Red
        return
    }

    $vmResult = $null
    if ([string]::IsNullOrWhiteSpace($isoPath)) {
        $vmResult = New-LabVM -VMName $vmName -MemoryGB $memoryGB -VHDPath $vhdPath -SwitchName $GlobalLabConfig.Network.SwitchName -ProcessorCount $cpuCount
    } else {
        $vmResult = New-LabVM -VMName $vmName -MemoryGB $memoryGB -VHDPath $vhdPath -SwitchName $GlobalLabConfig.Network.SwitchName -ProcessorCount $cpuCount -IsoPath $isoPath
    }

    if ($vmResult.Status -eq 'OK' -or $vmResult.Status -eq 'AlreadyExists') {
        Add-LabRunEvent -Step 'add-vm' -Status 'ok' -Message ("Type={0}; VM={1}; Status={2}" -f $VMType, $vmName, $vmResult.Status) -RunEvents $RunEvents
        Write-LabStatus -Status OK -Message $vmResult.Message
    } else {
        Add-LabRunEvent -Step 'add-vm' -Status 'fail' -Message ("Type={0}; VM={1}; Status={2}; Msg={3}" -f $VMType, $vmName, $vmResult.Status, $vmResult.Message) -RunEvents $RunEvents
        Write-LabStatus -Status FAIL -Message $vmResult.Message
    }
}

function Invoke-AddVMMenu {
    Write-Host ''
    Write-Host '  ADD VM' -ForegroundColor Cyan
    Write-Host '   [1] Add additional Server VM' -ForegroundColor White
    Write-Host '   [2] Add additional Workstation VM' -ForegroundColor White
    Write-Host '   [X] Back' -ForegroundColor DarkGray

    $vmChoice = (Read-Host '  Select').Trim().ToUpperInvariant()
    switch ($vmChoice) {
        '1' { Invoke-AddVMWizard -VMType 'Server' }
        '2' { Invoke-AddVMWizard -VMType 'Workstation' }
        'X' { return }
        default { Write-Host '  Invalid selection.' -ForegroundColor Red }
    }
}

function Read-MenuCount {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [int]$DefaultValue = 0
    )

    $inputValue = (Read-Host ("  {0} [{1}]" -f $Prompt, $DefaultValue)).Trim()
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return $DefaultValue
    }

    $count = 0
    if ([int]::TryParse($inputValue, [ref]$count) -and $count -ge 0) {
        return $count
    }

    Write-Host '  Invalid value; using default.' -ForegroundColor Yellow
    return $DefaultValue
}

function Invoke-BulkAdditionalVMProvision {
    param(
        [Parameter(Mandatory)][ValidateRange(0, 100)][int]$ServerCount,
        [Parameter(Mandatory)][ValidateRange(0, 100)][int]$WorkstationCount,
        [string]$ServerIsoPath,
        [string]$WorkstationIsoPath
    )

    $total = $ServerCount + $WorkstationCount
    if ($total -eq 0) { return }

    $serverMemoryGB = [int]([math]::Ceiling($GlobalLabConfig.VMSizing.Server.Memory / 1GB))
    $workstationMemoryGB = [int]([math]::Ceiling($GlobalLabConfig.VMSizing.Client.Memory / 1GB))
    $serverCpu = [int]$GlobalLabConfig.VMSizing.Server.Processors
    $workstationCpu = [int]$GlobalLabConfig.VMSizing.Client.Processors

    $diskRoot = Join-Path (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name) 'Disks'
    if (-not (Test-Path $diskRoot)) {
        New-Item -Path $diskRoot -ItemType Directory -Force | Out-Null
    }

    $existingNames = @()
    try {
        $existingNames = @(Hyper-V\Get-VM -ErrorAction Stop | Select-Object -ExpandProperty Name)
    } catch {
        $existingNames = @()
    }

    $newVmCmd = Get-Command New-LabVM -ErrorAction SilentlyContinue
    if (-not $newVmCmd) {
        throw 'New-LabVM function is not available in this session.'
    }

    for ($i = 0; $i -lt $ServerCount; $i++) {
        $suffix = 2
        while ($existingNames -contains ("SVR{0}" -f $suffix)) { $suffix++ }
        $vmName = "SVR{0}" -f $suffix
        $existingNames += $vmName
        $vhdPath = Join-Path $diskRoot ("{0}.vhdx" -f $vmName)

        if ([string]::IsNullOrWhiteSpace($ServerIsoPath)) {
            $result = New-LabVM -VMName $vmName -MemoryGB $serverMemoryGB -VHDPath $vhdPath -SwitchName $GlobalLabConfig.Network.SwitchName -ProcessorCount $serverCpu
        } else {
            $result = New-LabVM -VMName $vmName -MemoryGB $serverMemoryGB -VHDPath $vhdPath -SwitchName $GlobalLabConfig.Network.SwitchName -ProcessorCount $serverCpu -IsoPath $ServerIsoPath
        }

        if ($result.Status -eq 'OK' -or $result.Status -eq 'AlreadyExists') {
            Add-LabRunEvent -Step 'setup-add-server-vm' -Status 'ok' -Message ("{0}: {1}" -f $vmName, $result.Status) -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message ("Provisioned server VM {0}: {1}" -f $vmName, $result.Status)
        } else {
            Add-LabRunEvent -Step 'setup-add-server-vm' -Status 'fail' -Message ("{0}: {1} {2}" -f $vmName, $result.Status, $result.Message) -RunEvents $RunEvents
            Write-LabStatus -Status FAIL -Message ("Failed to provision server VM {0}: {1}" -f $vmName, $result.Message)
        }
    }

    for ($i = 0; $i -lt $WorkstationCount; $i++) {
        $suffix = 2
        while ($existingNames -contains ("WS{0}" -f $suffix)) { $suffix++ }
        $vmName = "WS{0}" -f $suffix
        $existingNames += $vmName
        $vhdPath = Join-Path $diskRoot ("{0}.vhdx" -f $vmName)

        if ([string]::IsNullOrWhiteSpace($WorkstationIsoPath)) {
            $result = New-LabVM -VMName $vmName -MemoryGB $workstationMemoryGB -VHDPath $vhdPath -SwitchName $GlobalLabConfig.Network.SwitchName -ProcessorCount $workstationCpu
        } else {
            $result = New-LabVM -VMName $vmName -MemoryGB $workstationMemoryGB -VHDPath $vhdPath -SwitchName $GlobalLabConfig.Network.SwitchName -ProcessorCount $workstationCpu -IsoPath $WorkstationIsoPath
        }

        if ($result.Status -eq 'OK' -or $result.Status -eq 'AlreadyExists') {
            Add-LabRunEvent -Step 'setup-add-workstation-vm' -Status 'ok' -Message ("{0}: {1}" -f $vmName, $result.Status) -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message ("Provisioned workstation VM {0}: {1}" -f $vmName, $result.Status)
        } else {
            Add-LabRunEvent -Step 'setup-add-workstation-vm' -Status 'fail' -Message ("{0}: {1} {2}" -f $vmName, $result.Status, $result.Message) -RunEvents $RunEvents
            Write-LabStatus -Status FAIL -Message ("Failed to provision workstation VM {0}: {1}" -f $vmName, $result.Message)
        }
    }
}

function Invoke-SetupLabMenu {
    Write-Host ''
    Write-Host '  SETUP LAB' -ForegroundColor Cyan
    Write-Host '  Core build always includes DC1 + SVR1 + WS1.' -ForegroundColor DarkGray

    $serverCount = Read-MenuCount -Prompt 'Additional server VMs to provision' -DefaultValue 0
    $workstationCount = Read-MenuCount -Prompt 'Additional workstation VMs to provision' -DefaultValue 0

    $serverIso = ''
    $workstationIso = ''
    if ($serverCount -gt 0) {
        $serverIso = (Read-Host '  Server ISO path (optional)').Trim()
    }
    if ($workstationCount -gt 0) {
        $workstationIso = (Read-Host '  Workstation ISO path (optional)').Trim()
    }

    Add-LabRunEvent -Step 'setup-plan' -Status 'ok' -Message ("ExtraServers={0}; ExtraWorkstations={1}" -f $serverCount, $workstationCount) -RunEvents $RunEvents

    Invoke-OneButtonSetup

    if (($serverCount + $workstationCount) -gt 0) {
        Write-Host ''
        Write-Host '  Provisioning additional VMs...' -ForegroundColor Cyan
        Invoke-BulkAdditionalVMProvision -ServerCount $serverCount -WorkstationCount $workstationCount -ServerIsoPath $serverIso -WorkstationIsoPath $workstationIso
    }
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   OPENCODE LAB APP" -ForegroundColor Cyan
    Write-Host ("   {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Gray
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  SETUP" -ForegroundColor DarkCyan
    Write-Host "   [S] Setup Lab      Bootstrap + Deploy + optional extra VMs"
    Write-Host "   [R] Reset Lab      Blow away + Rebuild"
    Write-Host ""
    Write-Host "  MANAGE" -ForegroundColor DarkCyan
    Write-Host "   [1] Start    [4] Rollback    [7] Terminal"
    Write-Host "   [2] Stop     [5] Health      [8] New Project"
    Write-Host "   [3] Status   [6] Push/Save   [9] Test"
    Write-Host "   [A] Asset Report"
    Write-Host "   [F] Offline AL Bundle"
    Write-Host "   [O] Configure Role"
    Write-Host "   [V] Add VM"
    Write-Host ""
    Write-Host "  LINUX" -ForegroundColor DarkCyan
    Write-Host "   [L] Add LIN1 (Ubuntu)"
    Write-Host "   [C] Configure LIN1"
    Write-Host "   [N] Install Ansible"
    Write-Host ""
    Write-Host "  [X] Exit" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-InteractiveMenu {
    do {
        Show-Menu
        $choice = (Read-Host "  Select").Trim().ToUpperInvariant()
        switch ($choice) {
            'S' { Invoke-MenuCommand -Name 'setup' -Command { Invoke-SetupLabMenu } }
            'R' {
                Invoke-MenuCommand -Name 'reset' -Command {
                    $confirm = (Read-Host "  Type REBUILD to confirm").Trim()
                    if ($confirm -eq 'REBUILD') {
                        $dropNet = (Read-Host "  Remove network? (y/n)").Trim().ToLowerInvariant() -eq 'y'
                        Invoke-OneButtonReset -DropNetwork:$dropNet
                    } else {
                        Write-Host "  Cancelled" -ForegroundColor Yellow
                    }
                }
            }
            '1' { Invoke-MenuCommand -Name 'start' -Command { Invoke-LabRepoScript -BaseName 'Start-LabDay' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            '2' { Invoke-MenuCommand -Name 'stop' -Command { Stop-LabVMsSafe; Write-LabStatus -Status OK -Message "Lab stopped" } }
            '3' { Invoke-MenuCommand -Name 'status' -Command { Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            '4' {
                Invoke-MenuCommand -Name 'rollback' -Command {
                    Ensure-LabImported
                    if (-not (Test-LabReadySnapshot)) {
                        Write-LabStatus -Status WARN -Message "LabReady snapshot not found"
                        return
                    }
                    Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
                    Write-LabStatus -Status OK -Message "Restored to LabReady"
                }
            }
            '5' { Invoke-MenuCommand -Name 'health' -Command { $healthArgs = Get-LabHealthArgs; Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            '6' {
                Write-Host "  [P] Push to WS1  [S] Save Work" -ForegroundColor Cyan
                $sub = (Read-Host "  Select").Trim().ToUpperInvariant()
                if ($sub -eq 'P') { Invoke-LabRepoScript -BaseName 'Push-ToWS1' -ScriptDir $ScriptDir -RunEvents $RunEvents }
                elseif ($sub -eq 'S') { Invoke-LabRepoScript -BaseName 'Save-LabWork' -ScriptDir $ScriptDir -RunEvents $RunEvents }
            }
            '7' { Invoke-MenuCommand -Name 'terminal' -Command { Invoke-LabRepoScript -BaseName 'Open-LabTerminal' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            '8' { Invoke-MenuCommand -Name 'new-project' -Command { Invoke-LabRepoScript -BaseName 'New-LabProject' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            '9' { Invoke-MenuCommand -Name 'test' -Command { Invoke-LabRepoScript -BaseName 'Test-OnWS1' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            'A' { Invoke-MenuCommand -Name 'asset-report' -Command { Invoke-LabRepoScript -BaseName 'Asset-Report' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            'F' { Invoke-MenuCommand -Name 'offline-bundle' -Command { Invoke-LabRepoScript -BaseName 'Build-OfflineAutomatedLabBundle' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            'O' { Invoke-MenuCommand -Name 'configure-role' -Command { Invoke-ConfigureRoleMenu } }
            'V' { Invoke-MenuCommand -Name 'add-vm' -Command { Invoke-AddVMMenu } }
            'L' { Invoke-MenuCommand -Name 'add-lin1' -Command { Invoke-LabRepoScript -BaseName 'Add-LIN1' -Arguments @('-NonInteractive') -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            'C' { Invoke-MenuCommand -Name 'lin1-config' -Command { Invoke-LabRepoScript -BaseName 'Configure-LIN1' -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            'N' { Invoke-MenuCommand -Name 'ansible' -Command { Invoke-LabRepoScript -BaseName 'Install-Ansible' -Arguments @('-NonInteractive') -ScriptDir $ScriptDir -RunEvents $RunEvents } }
            'X' { break }
            default { Write-Host "  Invalid" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    } while ($choice -ne 'X')
}

$runSuccess = $false
$runError = ''
$hostOutcomes = @()
$blastRadius = @()
$executionOutcome = 'not_dispatched'
$executionStartedAt = $null
$executionCompletedAt = $null
$dispatchResult = $null
$skipLegacyOrchestration = $false

    try {
        $rawAction = $Action
        $rawMode = $Mode
        $orchestrationAction = $null
        $operationIntent = $null
        $fleetProbe = @()
        $policyDecision = $null
        $policyOutcome = $null
        $policyReason = $null
        $hostOutcomes = @()
        $blastRadius = @()

    if (Get-Command Resolve-LabDispatchPlan -ErrorAction SilentlyContinue) {
        $dispatchPlan = Resolve-LabDispatchPlan -Action $rawAction -Mode $rawMode
        $Action = $dispatchPlan.DispatchAction
        $RequestedMode = $dispatchPlan.Mode
        $orchestrationAction = $dispatchPlan.OrchestrationAction
    }
    elseif (Get-Command Resolve-LabActionRequest -ErrorAction SilentlyContinue) {
        $request = Resolve-LabActionRequest -Action $rawAction -Mode $rawMode
        $Action = $request.Action
        $RequestedMode = $request.Mode
        if ($Action -in @('deploy', 'teardown')) {
            $orchestrationAction = $Action
        }
    }
    else {
        $Action = $rawAction
        $RequestedMode = $rawMode
        if ($Action -in @('deploy', 'teardown')) {
            $orchestrationAction = $Action
        }
    }

    $executionProfile = $null
    $modeDecision = $null
    $stateProbe = $null
    $orchestrationIntent = $null

    if ($orchestrationAction -in @('deploy', 'teardown')) {
        $operationIntentSplat = @{
            Action = $orchestrationAction
            Mode = $RequestedMode
        }
        if ($TargetHosts) {
            $operationIntentSplat.TargetHosts = @($TargetHosts)
        }
        if (-not [string]::IsNullOrWhiteSpace($InventoryPath)) {
            $operationIntentSplat.InventoryPath = $InventoryPath
        }
        $operationIntent = Resolve-LabOperationIntent @operationIntentSplat

        $resolvedTargetHosts = @($operationIntent.TargetHosts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $blastRadius = @($resolvedTargetHosts)
        if ($resolvedTargetHosts.Count -eq 0) {
            $policyOutcome = 'PolicyBlocked'
            $policyReason = 'target_hosts_empty'
            $EffectiveMode = $RequestedMode
            Add-LabRunEvent -Step 'policy' -Status 'blocked' -Message $policyReason -RunEvents $RunEvents

            if ($NoExecute) {
                $runSuccess = $true
                Add-LabRunEvent -Step 'run' -Status 'ok' -Message 'no-execute routing only (policy blocked)' -RunEvents $RunEvents
                return [pscustomobject]@{
                    RawAction = $rawAction
                    RawMode = $rawMode
                    DispatchAction = $Action
                    OrchestrationAction = $orchestrationAction
                    DispatchMode = $ResolvedDispatchMode
                    ExecutionOutcome = $executionOutcome
                    ExecutionStartedAt = $executionStartedAt
                    ExecutionCompletedAt = $executionCompletedAt
                    RequestedMode = $RequestedMode
                    EffectiveMode = $EffectiveMode
                    FallbackReason = $FallbackReason
                    ProfileSource = $ProfileSource
                    OperationIntent = $operationIntent
                    FleetProbe = $fleetProbe
                    StateProbe = $stateProbe
                    PolicyOutcome = $policyOutcome
                    PolicyReason = $policyReason
                    HostOutcomes = @($hostOutcomes)
                    BlastRadius = @($blastRadius)
                    ModeDecision = $modeDecision
                    OrchestrationIntent = $orchestrationIntent
                }
            }

            throw "Policy blocked execution: $policyReason"
        }

        $operationIntent.TargetHosts = $resolvedTargetHosts

        $stateProbe = Resolve-NoExecuteStateOverride
        if ($null -eq $stateProbe) {
            $stateProbe = Resolve-RuntimeStateOverride
        }
        if ($null -eq $stateProbe) {
            $fleetProbe = @(Get-LabFleetStateProbe -HostNames $operationIntent.TargetHosts -LabName $GlobalLabConfig.Lab.Name -VMNames (Get-LabExpectedVMs -LabConfig $GlobalLabConfig) -SwitchName $SwitchName -NatName $GlobalLabConfig.Network.NatName)
        }
        elseif ($stateProbe -is [System.Array]) {
            $fleetProbe = @($stateProbe)
        }
        else {
            $statePropertyNames = @($stateProbe.PSObject.Properties.Name)
            $isLegacySingleState = ($statePropertyNames -contains 'LabRegistered') -or
                ($statePropertyNames -contains 'MissingVMs') -or
                ($statePropertyNames -contains 'LabReadyAvailable') -or
                ($statePropertyNames -contains 'SwitchPresent') -or
                ($statePropertyNames -contains 'NatPresent')

            if ($isLegacySingleState) {
                $legacyHostName = if ($operationIntent.TargetHosts.Count -gt 0) { [string]$operationIntent.TargetHosts[0] } else { 'local' }
                $fleetProbe = @(
                    [pscustomobject]@{
                        HostName = $legacyHostName
                        Reachable = $true
                        Probe = $stateProbe
                        Failure = $null
                    }
                )
            }
            else {
                $fleetProbe = @($stateProbe)
            }
        }

        if ($fleetProbe.Count -eq 0) {
            $fleetProbe = @(
                [pscustomobject]@{
                    HostName = 'local'
                    Reachable = $true
                    Probe = [pscustomobject]@{
                        LabRegistered = $false
                        MissingVMs = @('unknown')
                        LabReadyAvailable = $false
                        SwitchPresent = $false
                        NatPresent = $false
                    }
                    Failure = $null
                }
            )
        }

        $hostOutcomes = @($fleetProbe)

        $policyHostProbes = @($fleetProbe | ForEach-Object {
            $probeHostName = if ($_.PSObject.Properties.Name -contains 'HostName' -and -not [string]::IsNullOrWhiteSpace([string]$_.HostName)) {
                [string]$_.HostName
            }
            elseif ($_.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$_.Name)) {
                [string]$_.Name
            }
            else {
                'unknown'
            }

            [pscustomobject]@{
                Name = $probeHostName
                Reachable = if ($_.PSObject.Properties.Name -contains 'Reachable') { [bool]$_.Reachable } else { $false }
            }
        })

        $safetyRequiresFull = $false
        if ($orchestrationAction -eq 'teardown' -and $RequestedMode -eq 'quick') {
            $safetyRequiresFull = @($fleetProbe | Where-Object {
                ($_.PSObject.Properties.Name -contains 'Reachable') -and
                [bool]$_.Reachable -and
                (-not ($_.PSObject.Properties.Name -contains 'Probe') -or
                 -not ($_.Probe.PSObject.Properties.Name -contains 'LabReadyAvailable') -or
                 -not [bool]$_.Probe.LabReadyAvailable)
            }).Count -gt 0
        }

        $hasScopedConfirmation = $false
        $scopedConfirmationFailureReason = $null
        $confirmationRunScope = $null
        $confirmationSecret = $null
        if (-not [string]::IsNullOrWhiteSpace($ConfirmationToken)) {
            $confirmationRunScope = if (-not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_CONFIRMATION_RUN_ID)) {
                [string]$env:OPENCODELAB_CONFIRMATION_RUN_ID
            }
            else {
                $RunId
            }

            $confirmationOperationHash = '{0}:{1}:{2}' -f $orchestrationAction, $RequestedMode, $Action
            $confirmationSecret = if (-not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_CONFIRMATION_SECRET)) {
                [string]$env:OPENCODELAB_CONFIRMATION_SECRET
            }
            elseif (Get-Variable -Name LabScopedConfirmationSecret -ErrorAction SilentlyContinue) {
                [string]$LabScopedConfirmationSecret
            }
            else {
                $null
            }

            if (-not (Get-Command Test-LabScopedConfirmationToken -ErrorAction SilentlyContinue)) {
                $scopedConfirmationFailureReason = 'scoped_confirmation_validator_unavailable'
            }
            elseif ([string]::IsNullOrWhiteSpace($confirmationSecret)) {
                $scopedConfirmationFailureReason = 'scoped_confirmation_secret_unavailable'
            }
            else {
                $confirmationValidation = Test-LabScopedConfirmationToken -Token $ConfirmationToken -RunId $confirmationRunScope -TargetHosts $resolvedTargetHosts -OperationHash $confirmationOperationHash -Secret $confirmationSecret
                if ($confirmationValidation.Valid) {
                    $hasScopedConfirmation = $true
                }
                else {
                    $scopedConfirmationFailureReason = 'scoped_confirmation_invalid:{0}' -f ([string]$confirmationValidation.Reason)
                }
            }
        }

        $policyDecision = Resolve-LabCoordinatorPolicy -Action $orchestrationAction -RequestedMode $RequestedMode -HostProbes $policyHostProbes -SafetyRequiresFull:$safetyRequiresFull -HasScopedConfirmation:$hasScopedConfirmation
        $policyOutcome = $policyDecision.Outcome.ToString()
        $policyReason = [string]$policyDecision.Reason

        if (($policyReason -eq 'missing_scoped_confirmation') -and (-not [string]::IsNullOrWhiteSpace($scopedConfirmationFailureReason))) {
            $policyReason = $scopedConfirmationFailureReason
        }

        if (-not $policyDecision.Allowed) {
            if ($policyDecision.PSObject.Properties.Name -contains 'EffectiveMode' -and -not [string]::IsNullOrWhiteSpace([string]$policyDecision.EffectiveMode)) {
                $EffectiveMode = [string]$policyDecision.EffectiveMode
            }
            Add-LabRunEvent -Step 'policy' -Status 'blocked' -Message $policyReason -RunEvents $RunEvents

            if ($NoExecute) {
                $runSuccess = $true
                Add-LabRunEvent -Step 'run' -Status 'ok' -Message 'no-execute routing only (policy blocked)' -RunEvents $RunEvents
                return [pscustomobject]@{
                    RawAction = $rawAction
                    RawMode = $rawMode
                    DispatchAction = $Action
                    OrchestrationAction = $orchestrationAction
                    DispatchMode = $ResolvedDispatchMode
                    ExecutionOutcome = $executionOutcome
                    ExecutionStartedAt = $executionStartedAt
                    ExecutionCompletedAt = $executionCompletedAt
                    RequestedMode = $RequestedMode
                    EffectiveMode = $EffectiveMode
                    FallbackReason = $FallbackReason
                    ProfileSource = $ProfileSource
                    OperationIntent = $operationIntent
                    FleetProbe = $fleetProbe
                    StateProbe = $stateProbe
                    PolicyOutcome = $policyOutcome
                    PolicyReason = $policyReason
                    HostOutcomes = @($hostOutcomes)
                    BlastRadius = @($blastRadius)
                    ModeDecision = $modeDecision
                    OrchestrationIntent = $orchestrationIntent
                }
            }

            throw "Policy blocked execution: $policyReason"
        }

        Add-LabRunEvent -Step 'policy' -Status 'ok' -Message ("outcome={0}; reason={1}; requested_mode={2}; effective_mode={3}" -f $policyOutcome, $policyReason, $RequestedMode, $policyDecision.EffectiveMode) -RunEvents $RunEvents

        $stateProbe = $null
        $firstReachable = @($fleetProbe | Where-Object {
            ($_.PSObject.Properties.Name -contains 'Reachable') -and
            [bool]$_.Reachable -and
            ($_.PSObject.Properties.Name -contains 'Probe') -and
            $null -ne $_.Probe
        }) | Select-Object -First 1

        if ($firstReachable) {
            $stateProbe = $firstReachable.Probe
        }

        if ($null -eq $stateProbe) {
            $stateProbe = [pscustomobject]@{
                LabRegistered = $false
                MissingVMs = @('unknown')
                LabReadyAvailable = $false
                SwitchPresent = $false
                NatPresent = $false
            }
        }

        if (-not ($stateProbe.PSObject.Properties.Name -contains 'MissingVMs')) {
            $stateProbe | Add-Member -NotePropertyName 'MissingVMs' -NotePropertyValue @()
        }

        $healResult = $null
        $hasGlobalLabConfig = (Test-Path variable:GlobalLabConfig) -and $null -ne $GlobalLabConfig
        $autoHealEnabled = if ($hasGlobalLabConfig -and $GlobalLabConfig.ContainsKey('AutoHeal')) {
            [bool]$GlobalLabConfig.AutoHeal.Enabled -and [bool]$AutoHeal
        } else { [bool]$AutoHeal }
        $hasHealInfraVars = (Test-Path variable:SwitchName) -and (Test-Path variable:NatName) -and (Test-Path variable:AddressSpace)
        if ($autoHealEnabled -and $RequestedMode -eq 'quick' -and (-not $NoExecute) -and $hasHealInfraVars) {
            $healSplat = @{
                StateProbe = $stateProbe
                SwitchName = $SwitchName
                NatName = $GlobalLabConfig.Network.NatName
                AddressSpace = $GlobalLabConfig.Network.AddressSpace
                VMNames = @(Get-LabExpectedVMs -LabConfig $GlobalLabConfig)
            }
            if ($hasGlobalLabConfig -and $GlobalLabConfig.ContainsKey('AutoHeal')) {
                if ($GlobalLabConfig.AutoHeal.ContainsKey('TimeoutSeconds')) {
                    $healSplat.TimeoutSeconds = $GlobalLabConfig.AutoHeal.TimeoutSeconds
                }
                if ($GlobalLabConfig.AutoHeal.ContainsKey('HealthCheckTimeoutSeconds')) {
                    $healSplat.HealthCheckTimeoutSeconds = $GlobalLabConfig.AutoHeal.HealthCheckTimeoutSeconds
                }
            }
            $healResult = Invoke-LabQuickModeHeal @healSplat

            if ($healResult.HealAttempted) {
                foreach ($repair in $healResult.RepairsApplied) {
                    Write-Host "[AutoHeal] Repaired: $repair" -ForegroundColor Green
                    Add-LabRunEvent -Step 'auto_heal' -Status 'ok' -Message "repaired: $repair" -RunEvents $RunEvents
                }
                foreach ($issue in $healResult.RemainingIssues) {
                    Write-Host "[AutoHeal] Unresolved: $issue" -ForegroundColor Yellow
                    Add-LabRunEvent -Step 'auto_heal' -Status 'warn' -Message "unresolved: $issue" -RunEvents $RunEvents
                }
                if ($healResult.HealSucceeded) {
                    Write-Host "[AutoHeal] All issues healed. Continuing with quick mode." -ForegroundColor Green
                }
                elseif ($healResult.RepairsApplied.Count -gt 0) {
                    Write-Host "[AutoHeal] Some issues could not be healed. Falling back to full mode." -ForegroundColor Yellow
                }
                else {
                    Write-Host "[AutoHeal] No repairs possible. Falling back to full mode." -ForegroundColor Yellow
                }
                $stateProbe = Get-LabStateProbe -LabName $GlobalLabConfig.Lab.Name -VMNames (Get-LabExpectedVMs -LabConfig $GlobalLabConfig) -SwitchName $SwitchName -NatName $GlobalLabConfig.Network.NatName
            }
        }

        $modeDecision = Resolve-LabModeDecision -Operation $orchestrationAction -RequestedMode $RequestedMode -State $stateProbe
        $EffectiveMode = $modeDecision.EffectiveMode
        $FallbackReason = $modeDecision.FallbackReason

        $executionProfileSplat = @{
            Operation = $orchestrationAction
            Mode = $EffectiveMode
        }
        if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) {
            $executionProfileSplat.ProfilePath = $ProfilePath
        }
        $executionProfile = Resolve-LabExecutionProfile @executionProfileSplat

        $policyReevaluationRequired = $false
        $profileMode = if ($executionProfile.PSObject.Properties.Name -contains 'Mode') { [string]$executionProfile.Mode } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($profileMode) -and $profileMode -ne $EffectiveMode) {
            $isWeakerOverride = ($EffectiveMode -eq 'full') -and ($profileMode -eq 'quick')
            if (-not $isWeakerOverride) {
                $EffectiveMode = $profileMode
                $policyReevaluationRequired = $true
                if ($RequestedMode -ne $EffectiveMode) {
                    $FallbackReason = 'profile_mode_override'
                }
            }
        }

        if ($policyReevaluationRequired) {
            if (-not [string]::IsNullOrWhiteSpace($ConfirmationToken)) {
                $hasScopedConfirmation = $false
                $scopedConfirmationFailureReason = $null

                if (-not (Get-Command Test-LabScopedConfirmationToken -ErrorAction SilentlyContinue)) {
                    $scopedConfirmationFailureReason = 'scoped_confirmation_validator_unavailable'
                }
                elseif ([string]::IsNullOrWhiteSpace($confirmationSecret)) {
                    $scopedConfirmationFailureReason = 'scoped_confirmation_secret_unavailable'
                }
                else {
                    $overrideConfirmationOperationHash = '{0}:{1}:{2}' -f $orchestrationAction, $EffectiveMode, $Action
                    $overrideConfirmationValidation = Test-LabScopedConfirmationToken -Token $ConfirmationToken -RunId $confirmationRunScope -TargetHosts $resolvedTargetHosts -OperationHash $overrideConfirmationOperationHash -Secret $confirmationSecret
                    if ($overrideConfirmationValidation.Valid) {
                        $hasScopedConfirmation = $true
                    }
                    else {
                        $scopedConfirmationFailureReason = 'scoped_confirmation_invalid:{0}' -f ([string]$overrideConfirmationValidation.Reason)
                    }
                }
            }

            $policyDecisionAfterOverride = Resolve-LabCoordinatorPolicy -Action $orchestrationAction -RequestedMode $EffectiveMode -HostProbes $policyHostProbes -SafetyRequiresFull:$safetyRequiresFull -HasScopedConfirmation:$hasScopedConfirmation
            $policyOutcome = $policyDecisionAfterOverride.Outcome.ToString()
            $policyReason = [string]$policyDecisionAfterOverride.Reason

            if (($policyReason -eq 'missing_scoped_confirmation') -and (-not [string]::IsNullOrWhiteSpace($scopedConfirmationFailureReason))) {
                $policyReason = $scopedConfirmationFailureReason
            }

            if (-not $policyDecisionAfterOverride.Allowed) {
                if ($policyDecisionAfterOverride.PSObject.Properties.Name -contains 'EffectiveMode' -and -not [string]::IsNullOrWhiteSpace([string]$policyDecisionAfterOverride.EffectiveMode)) {
                    $EffectiveMode = [string]$policyDecisionAfterOverride.EffectiveMode
                }

                Add-LabRunEvent -Step 'policy' -Status 'blocked' -Message $policyReason -RunEvents $RunEvents

                if ($NoExecute) {
                    $runSuccess = $true
                    Add-LabRunEvent -Step 'run' -Status 'ok' -Message 'no-execute routing only (policy blocked)' -RunEvents $RunEvents
                    return [pscustomobject]@{
                        RawAction = $rawAction
                        RawMode = $rawMode
                        DispatchAction = $Action
                        OrchestrationAction = $orchestrationAction
                        DispatchMode = $ResolvedDispatchMode
                        ExecutionOutcome = $executionOutcome
                        ExecutionStartedAt = $executionStartedAt
                        ExecutionCompletedAt = $executionCompletedAt
                        RequestedMode = $RequestedMode
                        EffectiveMode = $EffectiveMode
                        FallbackReason = $FallbackReason
                        ProfileSource = $ProfileSource
                        OperationIntent = $operationIntent
                        FleetProbe = $fleetProbe
                        StateProbe = $stateProbe
                        PolicyOutcome = $policyOutcome
                        PolicyReason = $policyReason
                        HostOutcomes = @($hostOutcomes)
                        BlastRadius = @($blastRadius)
                        ModeDecision = $modeDecision
                        OrchestrationIntent = $orchestrationIntent
                    }
                }

                throw "Policy blocked execution: $policyReason"
            }

            Add-LabRunEvent -Step 'policy' -Status 'ok' -Message ("outcome={0}; reason={1}; requested_mode={2}; effective_mode={3}" -f $policyOutcome, $policyReason, $EffectiveMode, $policyDecisionAfterOverride.EffectiveMode) -RunEvents $RunEvents
        }

        $orchestrationIntent = Resolve-LabOrchestrationIntent -Action $orchestrationAction -EffectiveMode $EffectiveMode
        Add-LabRunEvent -Step 'orchestration' -Status 'ok' -Message ("raw_action={0}; action={1}; orchestration_action={2}; requested_mode={3}; effective_mode={4}; strategy={5}; fallback={6}; profile_source={7}" -f $rawAction, $Action, $orchestrationAction, $RequestedMode, $EffectiveMode, $orchestrationIntent.Strategy, $FallbackReason, $ProfileSource) -RunEvents $RunEvents
    }
    else {
        $EffectiveMode = $RequestedMode
        Add-LabRunEvent -Step 'orchestration' -Status 'ok' -Message ("raw_action={0}; action={1}; requested_mode={2}; effective_mode={3}; profile_source={4}" -f $rawAction, $Action, $RequestedMode, $EffectiveMode, $ProfileSource) -RunEvents $RunEvents
    }

    if ($NoExecute) {
        $runSuccess = $true
        Add-LabRunEvent -Step 'run' -Status 'ok' -Message 'no-execute routing only' -RunEvents $RunEvents
        return [pscustomobject]@{
            RawAction = $rawAction
            RawMode = $rawMode
            DispatchAction = $Action
            OrchestrationAction = $orchestrationAction
            DispatchMode = $ResolvedDispatchMode
            ExecutionOutcome = $executionOutcome
            ExecutionStartedAt = $executionStartedAt
            ExecutionCompletedAt = $executionCompletedAt
            RequestedMode = $RequestedMode
            EffectiveMode = $EffectiveMode
            FallbackReason = $FallbackReason
            ProfileSource = $ProfileSource
            OperationIntent = $operationIntent
            FleetProbe = $fleetProbe
            StateProbe = $stateProbe
            PolicyOutcome = $policyOutcome
            PolicyReason = $policyReason
            HostOutcomes = @($hostOutcomes)
            BlastRadius = @($blastRadius)
            ModeDecision = $modeDecision
            OrchestrationIntent = $orchestrationIntent
        }
    }

    $dispatchUsesCoordinator = $ResolvedDispatchMode -in @('canary', 'enforced')
    $dispatcherUnavailableInTestMode = $SkipRuntimeBootstrap -and
        (-not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_TEST_DISABLE_COORDINATOR_DISPATCH))
    $dispatcherAvailable = (-not $dispatcherUnavailableInTestMode) -and
        (Get-Command Invoke-LabCoordinatorDispatch -ErrorAction SilentlyContinue)

    if ((-not $NoExecute) -and $dispatchUsesCoordinator -and (-not $dispatcherAvailable)) {
        throw "Dispatch mode $ResolvedDispatchMode requires Invoke-LabCoordinatorDispatch, but it is unavailable."
    }

    $canInvokeCoordinatorDispatch = (-not $NoExecute) -and
        $dispatchUsesCoordinator -and
        ($orchestrationAction -in @('deploy', 'teardown')) -and
        ($policyOutcome -eq 'Approved') -and
        ($null -ne $operationIntent) -and
        (@($operationIntent.TargetHosts).Count -gt 0) -and
        $dispatcherAvailable

    if ($canInvokeCoordinatorDispatch) {
        Add-LabRunEvent -Step 'dispatch' -Status 'start' -Message ("action={0}; mode={1}; dispatch_mode={2}; targets={3}" -f $orchestrationAction, $EffectiveMode, $ResolvedDispatchMode, (@($operationIntent.TargetHosts).Count)) -RunEvents $RunEvents

        $dispatchSplat = @{
            Action = $orchestrationAction
            EffectiveMode = $EffectiveMode
            DispatchMode = $ResolvedDispatchMode
            TargetHosts = @($operationIntent.TargetHosts)
            MaxRetryCount = 2
            RetryDelayMilliseconds = 200
        }

        $failureHosts = @()
        if ($SkipRuntimeBootstrap -and -not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_TEST_DISPATCH_FAILURE_HOSTS)) {
            $failureHosts = @($env:OPENCODELAB_TEST_DISPATCH_FAILURE_HOSTS.Split(',') | ForEach-Object { [string]$_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        $dispatchMarkerPath = $null
        if ($SkipRuntimeBootstrap -and -not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_TEST_DISPATCH_EXECUTION_MARKER)) {
            $dispatchMarkerPath = [string]$env:OPENCODELAB_TEST_DISPATCH_EXECUTION_MARKER
        }

        $allowSimulatedRemote = $false
        if ($SkipRuntimeBootstrap -and -not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_TEST_ALLOW_SIMULATED_REMOTE_SUCCESS)) {
            $allowSimulatedRemote = $true
        }

        $localDispatchExecutor = {
            param($DispatchAction, $DispatchEffectiveMode)

            Invoke-OrchestrationActionCore -OrchestrationAction $DispatchAction -Mode $DispatchEffectiveMode -Intent $orchestrationIntent
            return $true
        }.GetNewClosure()

        $dispatchSplat.HostStepRunner = {
            param($HostName, $DispatchAction, $DispatchEffectiveMode, $Attempt)

            $normalizedHostName = [string]$HostName
            if ($dispatchMarkerPath) {
                "host=$normalizedHostName;action=$DispatchAction;mode=$DispatchEffectiveMode;attempt=$Attempt" | Add-Content -Path $dispatchMarkerPath -Encoding UTF8
            }

            if ($failureHosts -contains $normalizedHostName) {
                return $false
            }

            $isLocalTarget = $false
            $hostNameLower = $normalizedHostName.ToLowerInvariant()
            if ($hostNameLower -in @('local', 'localhost', '.', [Environment]::MachineName.ToLowerInvariant())) {
                $isLocalTarget = $true
            }

            if ($isLocalTarget) {
                if ($SkipRuntimeBootstrap -and (-not [string]::IsNullOrWhiteSpace($env:OPENCODELAB_TEST_SIMULATE_LOCAL_DISPATCH_SUCCESS))) {
                    return $true
                }

                return (& $localDispatchExecutor $DispatchAction $DispatchEffectiveMode)
            }

            if ($allowSimulatedRemote) {
                return $true
            }

            throw "Remote dispatch target '$normalizedHostName' requires an explicit remote execution implementation."
        }.GetNewClosure()

        $dispatchResult = Invoke-LabCoordinatorDispatch @dispatchSplat

        if ($null -ne $dispatchResult) {
            $hostOutcomes = @($dispatchResult.HostOutcomes)
            $executionOutcome = [string]$dispatchResult.ExecutionOutcome
            $executionStartedAt = $dispatchResult.ExecutionStartedAt
            $executionCompletedAt = $dispatchResult.ExecutionCompletedAt

            Add-LabRunEvent -Step 'dispatch' -Status 'ok' -Message ("outcome={0}; host_outcomes={1}" -f $executionOutcome, (@($hostOutcomes).Count)) -RunEvents $RunEvents
        }

        $skipLegacyOrchestration = $true
        Add-LabRunEvent -Step 'dispatch' -Status 'ok' -Message ("legacy_orchestration_skipped=true; dispatch_mode={0}" -f $ResolvedDispatchMode) -RunEvents $RunEvents
    }

    if (-not $skipLegacyOrchestration) {
        $executionStartedAt = (Get-Date).ToUniversalTime().ToString('o')
        $executionOutcome = 'in_progress'
    }
    Add-LabRunEvent -Step 'run' -Status 'start' -Message "Action=$Action; Mode=$EffectiveMode" -RunEvents $RunEvents
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
            $preflightArgs = Get-LabPreflightArgs
            Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabPreflight' -Arguments $preflightArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'bootstrap' {
            $bootstrapArgs = Get-LabBootstrapArgs -Mode $EffectiveMode -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict
            Invoke-LabRepoScript -BaseName 'Bootstrap' -Arguments $bootstrapArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'deploy' {
            if ($skipLegacyOrchestration -and $orchestrationAction -eq 'deploy') {
                Add-LabRunEvent -Step 'deploy' -Status 'ok' -Message 'skipped legacy deploy path (dispatcher handled orchestration action)' -RunEvents $RunEvents
            }
            else {
                Invoke-OrchestrationActionCore -OrchestrationAction 'deploy' -Mode $EffectiveMode -Intent $orchestrationIntent
            }
        }
        'teardown' {
            if ($skipLegacyOrchestration -and $orchestrationAction -eq 'teardown') {
                Add-LabRunEvent -Step 'teardown' -Status 'ok' -Message 'skipped legacy teardown path (dispatcher handled orchestration action)' -RunEvents $RunEvents
            }
            else {
                Invoke-OrchestrationActionCore -OrchestrationAction 'teardown' -Mode $EffectiveMode -Intent $orchestrationIntent
            }
        }
        'add-lin1' {
            $linArgs = @('-NonInteractive')
            Invoke-LabRepoScript -BaseName 'Add-LIN1' -Arguments $linArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'lin1-config' {
            $linArgs = @()
            if ($NonInteractive) { $linArgs += '-NonInteractive' }
            Invoke-LabRepoScript -BaseName 'Configure-LIN1' -Arguments $linArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'ansible' {
            Invoke-LabRepoScript -BaseName 'Install-Ansible' -Arguments @('-NonInteractive') -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'health' {
            $healthArgs = Get-LabHealthArgs
            Invoke-LabRepoScript -BaseName 'Test-OpenCodeLabHealth' -Arguments $healthArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }

        'start' { Invoke-LabRepoScript -BaseName 'Start-LabDay' -ScriptDir $ScriptDir -RunEvents $RunEvents }
        'status' { Invoke-LabRepoScript -BaseName 'Lab-Status' -ScriptDir $ScriptDir -RunEvents $RunEvents }
        'asset-report' { Invoke-LabRepoScript -BaseName 'Asset-Report' -ScriptDir $ScriptDir -RunEvents $RunEvents }
        'offline-bundle' { Invoke-LabRepoScript -BaseName 'Build-OfflineAutomatedLabBundle' -ScriptDir $ScriptDir -RunEvents $RunEvents }
        'terminal' { Invoke-LabRepoScript -BaseName 'Open-LabTerminal' -ScriptDir $ScriptDir -RunEvents $RunEvents }
        'new-project' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart', '-Force') }
            Invoke-LabRepoScript -BaseName 'New-LabProject' -Arguments $scriptArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'push' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart', '-Force') }
            Invoke-LabRepoScript -BaseName 'Push-ToWS1' -Arguments $scriptArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'test' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart') }
            Invoke-LabRepoScript -BaseName 'Test-OnWS1' -Arguments $scriptArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'save' {
            $scriptArgs = @()
            if ($NonInteractive) { $scriptArgs += @('-NonInteractive', '-AutoStart') }
            Invoke-LabRepoScript -BaseName 'Save-LabWork' -Arguments $scriptArgs -ScriptDir $ScriptDir -RunEvents $RunEvents
        }
        'stop' {
            Add-LabRunEvent -Step 'stop' -Status 'start' -Message 'Stop-LabVMsSafe' -RunEvents $RunEvents
            Stop-LabVMsSafe
            Add-LabRunEvent -Step 'stop' -Status 'ok' -Message 'requested' -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message "Stop requested for all lab VMs" -Indent 0
        }
        'rollback' {
            Add-LabRunEvent -Step 'rollback' -Status 'start' -Message 'Restore-LabVMSnapshot LabReady' -RunEvents $RunEvents
            Ensure-LabImported
            if (-not (Test-LabReadySnapshot)) {
                throw "LabReady snapshot not found on one or more VMs. Re-run deploy to recreate baseline."
            }
            Restore-LabVMSnapshot -All -SnapshotName 'LabReady'
            Add-LabRunEvent -Step 'rollback' -Status 'ok' -Message 'LabReady restored' -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message "Restored to LabReady" -Indent 0
        }
        'blow-away' { Invoke-BlowAway -BypassPrompt:($Force -or $NonInteractive) -DropNetwork:$RemoveNetwork -Simulate:$DryRun }
    }
    if ($skipLegacyOrchestration) {
        if ([string]::IsNullOrWhiteSpace($executionOutcome)) {
            $executionOutcome = 'not_dispatched'
        }

        if ($executionOutcome -in @('failed', 'partial')) {
            $executionOutcome = 'failed'

            $failedHostSummaries = @($hostOutcomes | Where-Object {
                ($_.PSObject.Properties.Name -contains 'DispatchStatus') -and
                ([string]$_.DispatchStatus -eq 'failed')
            } | ForEach-Object {
                $failedHostName = if ($_.PSObject.Properties.Name -contains 'HostName' -and -not [string]::IsNullOrWhiteSpace([string]$_.HostName)) {
                    [string]$_.HostName
                }
                else {
                    'unknown'
                }

                $failedHostMessage = if ($_.PSObject.Properties.Name -contains 'LastFailureMessage' -and -not [string]::IsNullOrWhiteSpace([string]$_.LastFailureMessage)) {
                    [string]$_.LastFailureMessage
                }
                else {
                    'unknown_failure'
                }

                '{0}: {1}' -f $failedHostName, $failedHostMessage
            })

            $failureDetail = if ($failedHostSummaries.Count -gt 0) {
                $failedHostSummaries -join '; '
            }
            else {
                'no_failed_host_details'
            }

            throw "Coordinator dispatch did not succeed for action '$orchestrationAction'. Failed hosts: $failureDetail"
        }

        if ($null -eq $executionCompletedAt) {
            $executionCompletedAt = (Get-Date).ToUniversalTime().ToString('o')
        }

        $runSuccess = $true
        Add-LabRunEvent -Step 'run' -Status 'ok' -Message 'completed (dispatcher)' -RunEvents $RunEvents
    }
    else {
        $executionCompletedAt = (Get-Date).ToUniversalTime().ToString('o')
        $executionOutcome = 'succeeded'
        $runSuccess = $true
        Add-LabRunEvent -Step 'run' -Status 'ok' -Message 'completed' -RunEvents $RunEvents
    }
} catch {
    if ($executionOutcome -eq 'in_progress') {
        $executionOutcome = 'failed'
    }

    if (($null -eq $executionCompletedAt) -and ($null -ne $executionStartedAt)) {
        $executionCompletedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    $runError = $_.Exception.Message
    Add-LabRunEvent -Step 'run' -Status 'fail' -Message $runError -RunEvents $RunEvents
    throw
} finally {
    if ((-not $NoExecute) -or $WriteArtifactsInNoExecute) {
        Write-RunArtifacts -Success:$runSuccess -ErrorMessage $runError
        Invoke-LogRetention
    }
}
