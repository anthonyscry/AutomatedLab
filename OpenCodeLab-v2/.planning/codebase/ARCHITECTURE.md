# Architecture

**Analysis Date:** 2025-02-21

## Pattern Overview

**Overall:** Layered architecture with separation of concerns across PowerShell modules and WPF presentation layer.

**Key Characteristics:**
- Modular PowerShell design (Core, Domain, Infrastructure, Presentation)
- WPF desktop application layer for GUI interactions
- Clear separation between CLI and GUI execution paths
- Event-driven artifact and logging system
- State machine-based lab deployment orchestration

## Layers

**Presentation Layer (WPF):**
- Purpose: Provide graphical interface for lab management and deployment
- Location: `Views/`, `ViewModels/`, `App.xaml.cs`, `MainWindow.xaml`
- Contains: XAML views (Dashboard, Actions, Settings), C# ViewModels (ActionsViewModel, DashboardViewModel), UI models
- Depends on: OpenCodeLab.Services (LabDeploymentService, HyperVService)
- Used by: End users launching OpenCodeLab-V2.exe

**Application Layer (PowerShell):**
- Purpose: Orchestrate command execution and artifact management
- Location: `src/OpenCodeLab.App/OpenCodeLab.App.psm1`
- Contains: `Invoke-LabCliCommand` (CLI entry point), `Get-LabCommandMap`, `Resolve-LabExitCode`
- Depends on: Core, Domain modules
- Used by: CLI launcher (`scripts/opencodelab.ps1`), WPF service layer

**Domain Layer (PowerShell):**
- Purpose: Define lab actions, policies, and state machines
- Location: `src/OpenCodeLab.Domain/`
- Contains:
  - Actions: `Invoke-LabDeployAction`, `Invoke-LabTeardownAction`, `Invoke-LabPreflightAction`, `Invoke-LabStatusAction`, `Invoke-LabHealthAction`
  - State: `Invoke-LabDeployStateMachine` (deployment state orchestration)
  - Policy: `Resolve-LabTeardownPolicy` (teardown decision logic)
  - Utilities: `Resolve-LabFailureCategory` (error classification)
- Depends on: Core, Infrastructure layers
- Used by: Application layer for command dispatch

**Core Layer (PowerShell):**
- Purpose: Provide fundamental utilities for configuration, locking, and artifact management
- Location: `src/OpenCodeLab.Core/Public/`
- Contains:
  - Configuration: `Get-LabConfig`, `Test-LabConfigSchema`
  - Locking: `Enter-LabRunLock`, `Exit-LabRunLock` (prevents concurrent runs)
  - Artifacts: `New-LabRunArtifactSet`, `New-LabActionResult`, `Write-LabEvent`
- Depends on: None (foundational layer)
- Used by: All other layers

**Infrastructure Layer (PowerShell):**
- Purpose: Abstract platform-specific Hyper-V operations
- Location: `src/OpenCodeLab.Infrastructure.HyperV/Public/`
- Contains: `Test-HyperVPrereqs`, `Get-LabVmSnapshot`
- Depends on: None (isolated from other layers)
- Used by: Domain actions for VM operations

**Service Layer (C#):**
- Purpose: Bridge between WPF UI and PowerShell backend
- Location: `Services/`
- Contains:
  - `LabDeploymentService` (manages lab deployment via PowerShell scripts)
  - `HyperVService` (queries Hyper-V VM state)
- Depends on: Models, System.Management
- Used by: ViewModels for async operations

**Console Presentation Layer (PowerShell):**
- Purpose: Provide text-based output formatting
- Location: `src/OpenCodeLab.Presentation.Console/Public/`
- Contains: `Format-LabDashboardFrame`, `Show-LabDashboardAction`
- Depends on: Core
- Used by: Dashboard command for console output

## Data Flow

**CLI Execution Path:**

1. User runs: `.\scripts/opencodelab.ps1 -Command deploy -Mode full`
2. Launcher loads `OpenCodeLab.App` module
3. `Invoke-LabCliCommand` validates config, creates artifact set
4. Command dispatches to appropriate action (e.g., `Invoke-LabDeployAction`)
5. Action acquires lock via `Enter-LabRunLock`, then executes state machine
6. State machine returns execution result
7. Result persisted to artifact files (run.json, summary.txt, errors.json, events.jsonl)
8. Exit code resolved and returned

**WPF Execution Path:**

1. User launches `OpenCodeLab-V2.exe`
2. `App.xaml.cs` initializes WPF application
3. `MainWindow.xaml` displays tabs (Dashboard, Actions, Settings)
4. `ActionsViewModel` manages lab list and user commands
5. User clicks "Deploy Lab"
6. `ActionsViewModel.DeployLabAsync` invokes `LabDeploymentService.DeployLabAsync`
7. Service finds and executes `Deploy-Lab.ps1` PowerShell script
8. Script output streamed back via event callbacks
9. Progress updated in UI, logs written to `C:\LabSources\Logs`

**Artifact Creation Flow:**

1. `New-LabRunArtifactSet` creates output directory: `{LogRoot}/{RunId}/`
2. Files written during execution:
   - `run.json` - Full action result (serialized pscustomobject)
   - `summary.txt` - Plain text summary
   - `errors.json` - Error details only (if failed)
   - `events.jsonl` - Line-delimited JSON event log
3. `Write-LabEvent` appends to events.jsonl as actions progress
4. All written with UTF-8 encoding, no BOM

**State Management:**

- Lab configuration stored in `$config` (loaded from psd1 files or GUI input)
- Execution result tracked in `[pscustomobject]` with fields: RunId, Action, Succeeded, FailureCategory, ErrorCode, RecoveryHint, DurationMs, ArtifactPath
- Lock file prevents concurrent runs: `artifacts/logs/run.lock` (acquired/released via Core layer)
- VM state queried on-demand via `Get-LabVmSnapshot` or `HyperVService`

## Key Abstractions

**LabActionResult:**
- Purpose: Standardized execution result object
- Examples: Returned by all `Invoke-Lab*Action` functions
- Pattern: Created via `New-LabActionResult`, populated with status/error fields, serialized to artifacts

**LabRunArtifactSet:**
- Purpose: Encapsulates output directory structure and file paths
- Examples: Created once per execution, referenced throughout action
- Pattern: Contains RunId, Path, and file paths (RunFilePath, SummaryFilePath, ErrorsFilePath, EventsFilePath)

**LabConfig:**
- Purpose: Typed configuration object for lab definition
- Examples: `$config = Get-LabConfig -Path '...\lab.settings.psd1'`
- Pattern: Hashtable-based in PowerShell (psd1 import), C# class in Models/ for WPF

**RunLock:**
- Purpose: Filesystem-based mutual exclusion for concurrent run prevention
- Examples: `Enter-LabRunLock -LockPath '...\run.lock'`
- Pattern: Returns lock handle, must be explicitly released via `Exit-LabRunLock`

## Entry Points

**CLI Entry Point:**
- Location: `scripts/opencodelab.ps1`
- Triggers: User command line: `opencodelab.ps1 -Command <action> -Mode <mode>`
- Responsibilities:
  - Parse parameters (Command, Mode, Force, Output format, ConfigPath)
  - Import OpenCodeLab.App module
  - Execute Invoke-LabCliCommand
  - Handle startup errors with fallback artifact creation
  - Return exit code (0=success, 2=policy blocked, 3=config error, 4=unexpected exception)

**GUI Entry Point:**
- Location: `App.xaml.cs` OnStartup method
- Triggers: User double-clicks OpenCodeLab-V2.exe
- Responsibilities:
  - Register global exception handlers (UI thread + AppDomain)
  - Create log directory
  - Initialize MainWindow
  - Route all unhandled exceptions to crash logging

**WPF Action Triggers:**
- ActionsViewModel buttons (NewLabCommand, DeployLabCommand, etc.)
- Each triggers async method that calls LabDeploymentService
- Service spawns PowerShell process with Deploy-Lab.ps1 script

## Error Handling

**Strategy:** Layered categorization with recovery hints

**Patterns:**

1. **Synchronous Errors (Core/Domain):**
   - Caught at action level, categorized via `Resolve-LabFailureCategory`
   - FailureCategory: PolicyBlocked, ConfigError, OperationFailed, TimeoutExceeded, UnexpectedException
   - ErrorCode: Specific error identifier (e.g., RUN_LOCK_ACTIVE, DEPLOY_STEP_FAILED)
   - RecoveryHint: Human-readable message with resolution guidance

2. **Lock Acquisition Errors:**
   - Thrown as "PolicyBlocked: ..." exceptions by `Enter-LabRunLock`
   - Caught in action handlers, mapped to PolicyBlocked category
   - Exit code 2 returned to prevent concurrent execution

3. **Script Execution Errors (WPF):**
   - PowerShell process failures captured by `LabDeploymentService`
   - Output parsed for error patterns, logged to UI and file
   - Deployment continues with degraded state

4. **Startup Errors:**
   - Module import failures caught in launcher
   - Creates minimal artifact set with error details
   - Exit code 3 returned (config error)

## Cross-Cutting Concerns

**Logging:**
- PowerShell: `Write-LabEvent` appends to events.jsonl (JSONL format, one event per line)
- WPF: Direct file writes to `C:\LabSources\Logs` directory
- Output includes timestamp (ISO 8601), event type, action, mode, duration

**Validation:**
- Config: `Test-LabConfigSchema` validates psd1 structure before use
- Inputs: Each action function validates parameters (non-empty strings, enum values)
- Hyper-V: `Test-HyperVPrereqs` checks prerequisites before deployment

**Authentication:**
- No explicit authentication layer
- Assumes CLI runs with appropriate local admin privileges for PowerShell operations
- WPF requires local admin for Hyper-V operations

---

*Architecture analysis: 2025-02-21*
