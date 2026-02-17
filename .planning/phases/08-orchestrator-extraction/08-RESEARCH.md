# Phase 8: Orchestrator Extraction - Research

**Date:** 2026-02-17
**Phase:** 8 of 10
**Focus:** Extract inline functions from OpenCodeLab-App.ps1 to Private/ helpers

## Current State Analysis

### File Metrics
- OpenCodeLab-App.ps1: 2,012 lines
- Inline functions: 34
- Script-scoped state variables: ~20
- Existing Private/ helpers: 57 files
- Existing Pester tests: 566 passing

### Function Inventory (34 inline functions)

| # | Function | Lines | Script-Scope Deps | Calls To | Risk |
|---|----------|-------|-------------------|----------|------|
| 1 | Add-RunEvent | 152-165 | $RunEvents | - | Low |
| 2 | Write-RunArtifacts | 167-250 | $RunId, $Action, $RunStart, $RequestedMode, $EffectiveMode, $FallbackReason, $ProfileSource, $NonInteractive, $CoreOnly, $Force, $RemoveNetwork, $DryRun, $DefaultsFile, $RunLogRoot, $RunEvents, $executionOutcome, $executionStartedAt, $executionCompletedAt, $healResult, $policyOutcome, $policyReason, $hostOutcomes, $blastRadius | - | High |
| 3 | Invoke-LogRetention | 252-260 | $LogRetentionDays, $RunLogRoot | - | Low |
| 4 | Test-LabReadySnapshot | 262-286 | $GlobalLabConfig | Ensure-LabImported, Get-ExpectedVMs | Low |
| 5 | Resolve-ScriptPath | 301-309 | $ScriptDir | - | Low |
| 6 | Convert-ArgumentArrayToSplat | 311-336 | (none) | - | Low |
| 7 | Invoke-RepoScript | 338-360 | (none) | Resolve-ScriptPath, Add-RunEvent, Convert-ArgumentArrayToSplat | Low |
| 8 | Get-ExpectedVMs | 362-364 | $GlobalLabConfig | - | Low |
| 9 | Get-PreflightArgs | 366-368 | (none) | - | Low |
| 10 | Get-BootstrapArgs | 370-381 | $NonInteractive, $AutoFixSubnetConflict | - | Low |
| 11 | Get-DeployArgs | 383-394 | $NonInteractive, $AutoFixSubnetConflict | - | Low |
| 12 | Get-HealthArgs | 396-398 | (none) | - | Low |
| 13 | Invoke-OrchestrationActionCore | 400-433 | $Force, $NonInteractive, $RemoveNetwork, $DryRun | Invoke-QuickDeploy, Invoke-QuickTeardown, Get-DeployArgs, Invoke-RepoScript, Invoke-BlowAway | Med |
| 14 | Resolve-NoExecuteStateOverride | 435-482 | $NoExecute, $NoExecuteStateJson, $NoExecuteStatePath | - | Med |
| 15 | Resolve-RuntimeStateOverride | 484-530 | $SkipRuntimeBootstrap, env var | - | Med |
| 16 | Ensure-LabImported | 532-554 | $GlobalLabConfig | - | Low |
| 17 | Stop-LabVMsSafe | 556-565 | $GlobalLabConfig | Ensure-LabImported | Low |
| 18 | Invoke-BlowAway | 567-699 | $GlobalLabConfig, $SwitchName | Add-RunEvent, Stop-LabVMsSafe | Med |
| 19 | Invoke-OneButtonSetup | 701-751 | $EffectiveMode | Get-PreflightArgs, Get-BootstrapArgs, Invoke-RepoScript, Get-ExpectedVMs, Get-HealthArgs, Ensure-LabImported, Test-LabReadySnapshot, Add-RunEvent | Med |
| 20 | Invoke-OneButtonReset | 753-768 | $DryRun, $Force, $NonInteractive | Invoke-BlowAway, Invoke-OneButtonSetup, Add-RunEvent | Med |
| 21 | Invoke-Setup | 770-776 | $EffectiveMode | Get-PreflightArgs, Get-BootstrapArgs, Invoke-RepoScript | Low |
| 22 | Invoke-QuickDeploy | 778-791 | $DryRun | Invoke-RepoScript, Get-HealthArgs, Add-RunEvent | Low |
| 23 | Invoke-QuickTeardown | 793-821 | $DryRun | Stop-LabVMsSafe, Ensure-LabImported, Test-LabReadySnapshot, Get-ExpectedVMs, Add-RunEvent | Med |
| 24 | Pause-Menu | 823-825 | (none) | - | Low |
| 25 | Invoke-MenuCommand | 827-846 | (none) | Add-RunEvent, Pause-Menu | Low |
| 26 | Get-MenuVmSelection | 848-892 | $GlobalLabConfig | - | Low |
| 27 | Invoke-ConfigureRoleMenu | 894-961 | $ScriptDir | Get-MenuVmSelection, Add-RunEvent | Med |
| 28 | Invoke-AddVMWizard | 963-1039 | $GlobalLabConfig | Add-RunEvent | Med |
| 29 | Invoke-AddVMMenu | 1041-1055 | (none) | Invoke-AddVMWizard | Low |
| 30 | Read-MenuCount | 1057-1075 | (none) | - | Low |
| 31 | Invoke-BulkAdditionalVMProvision | 1077-1153 | $GlobalLabConfig | Add-RunEvent | Med |
| 32 | Invoke-SetupLabMenu | 1155-1181 | (none) | Read-MenuCount, Invoke-OneButtonSetup, Invoke-BulkAdditionalVMProvision, Add-RunEvent | Med |
| 33 | Show-Menu | 1183-1211 | (none) | - | Low |
| 34 | Invoke-InteractiveMenu | 1213-1265 | $SwitchName, $EffectiveMode | Show-Menu, Invoke-MenuCommand, many dispatched calls | High |

### Script-Scoped State Variables (set in main body, read by functions)

| Variable | Set At | Used By |
|----------|--------|---------|
| $ScriptDir | L61 | Resolve-ScriptPath, Invoke-ConfigureRoleMenu |
| $SwitchName | L122-127 | Invoke-BlowAway, Invoke-InteractiveMenu |
| $RunStart | L128 | Write-RunArtifacts |
| $RunId | L129 | Write-RunArtifacts |
| $RunLogRoot | L130 | Write-RunArtifacts, Invoke-LogRetention |
| $RunEvents | L132 | Add-RunEvent, Write-RunArtifacts |
| $RequestedMode | L133 | Write-RunArtifacts |
| $EffectiveMode | L134 | Write-RunArtifacts, Invoke-OneButtonSetup, Invoke-Setup |
| $FallbackReason | L135 | Write-RunArtifacts |
| $ProfileSource | L136 | Write-RunArtifacts |
| $ResolvedDispatchMode | L137 | Write-RunArtifacts |
| $NonInteractive | param | Get-BootstrapArgs, Get-DeployArgs, Invoke-OrchestrationActionCore, Invoke-OneButtonReset |
| $AutoFixSubnetConflict | param | Get-BootstrapArgs, Get-DeployArgs |
| $Force | param | Invoke-OrchestrationActionCore, Invoke-OneButtonReset |
| $RemoveNetwork | param | Invoke-OrchestrationActionCore |
| $DryRun | param | Invoke-OrchestrationActionCore, Invoke-OneButtonReset, Invoke-QuickDeploy, Invoke-QuickTeardown |
| $LogRetentionDays | param | Invoke-LogRetention |
| $NoExecute | param | Resolve-NoExecuteStateOverride |
| $NoExecuteStateJson | param | Resolve-NoExecuteStateOverride |
| $NoExecuteStatePath | param | Resolve-NoExecuteStateOverride |
| $DefaultsFile | param | Write-RunArtifacts |

### Extraction Strategy

**Approach:** Incremental extraction in 4 batches, ordered by dependency (leaf functions first).

**Batch 1 (Plan 08-01): Pure utility functions** -- 11 functions with no/minimal script-scope deps
Functions: Convert-ArgumentArrayToSplat, Resolve-ScriptPath, Invoke-RepoScript, Get-ExpectedVMs, Get-PreflightArgs, Get-BootstrapArgs, Get-DeployArgs, Get-HealthArgs, Ensure-LabImported, Add-RunEvent, Invoke-LogRetention

**Batch 2 (Plan 08-02): State resolution and lab operations** -- 8 functions
Functions: Resolve-NoExecuteStateOverride, Resolve-RuntimeStateOverride, Test-LabReadySnapshot, Stop-LabVMsSafe, Write-RunArtifacts, Invoke-BlowAway, Invoke-QuickDeploy, Invoke-QuickTeardown

**Batch 3 (Plan 08-03): Lifecycle orchestration** -- 6 functions
Functions: Invoke-OrchestrationActionCore, Invoke-OneButtonSetup, Invoke-OneButtonReset, Invoke-Setup, Invoke-BulkAdditionalVMProvision, Invoke-SetupLabMenu

**Batch 4 (Plan 08-04): Interactive menu system** -- 9 functions
Functions: Pause-Menu, Invoke-MenuCommand, Get-MenuVmSelection, Invoke-ConfigureRoleMenu, Invoke-AddVMWizard, Invoke-AddVMMenu, Read-MenuCount, Show-Menu, Invoke-InteractiveMenu

### Design Decisions

1. **Parameter injection for script-scope vars**: Each extracted function gets explicit parameters for the script-scope variables it reads. At the call site in App.ps1, these are passed in.

2. **$GlobalLabConfig handling**: Pass as parameter. Functions should not assume global state.

3. **Add-RunEvent becomes a shared helper**: Called by many functions. Extracted first with $RunEvents as a parameter. Call sites pass the shared list.

4. **Interactive functions**: Extract with Read-Host calls intact. They are testable by mocking Read-Host in Pester.

5. **Write-RunArtifacts**: Most script-scope dependencies. Extract with a single parameter object or many explicit parameters.

## Success Criteria (from ROADMAP)

1. All inline functions moved from OpenCodeLab-App.ps1 to Private/ helpers with proper naming conventions
2. Lab-Common.ps1 auto-loads extracted helpers (no explicit registration needed)
3. Each extracted helper has [CmdletBinding()], explicit parameters, and no script-scope variable dependencies
4. All 566 existing Pester tests continue passing after extraction (no behavior regression)
5. Extracted helpers are independently testable with unit tests
