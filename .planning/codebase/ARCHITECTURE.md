# Architecture

**Analysis Date:** 2026-02-16

## Pattern Overview

**Overall:** Layered orchestration with PowerShell module system and WPF GUI

**Key Characteristics:**
- PowerShell module-based architecture with Public/Private function separation
- Orchestrator pattern for workflow coordination (`OpenCodeLab-App.ps1`)
- State-driven decision engine for quick vs. full deployment modes
- WPF GUI with XAML-based views and PowerShell event handlers
- Role-based VM provisioning system

## Layers

**Orchestration Layer:**
- Purpose: Coordinates high-level workflows and user actions
- Location: `/mnt/c/projects/AutomatedLab/OpenCodeLab-App.ps1`
- Contains: Action routing, mode decision logic, confirmation gates, menu system
- Depends on: Lab-Config.ps1, Private helpers, Public commands, SimpleLab module
- Used by: Scripts/Run-OpenCodeLab.ps1, GUI actions, CLI invocations

**Module Layer:**
- Purpose: Provides reusable lab automation functions
- Location: `/mnt/c/projects/AutomatedLab/SimpleLab.psm1`
- Contains: Module manifest, auto-loading of Public/Private functions
- Depends on: Import-LabScriptTree.ps1 for dynamic discovery
- Used by: Orchestration layer, GUI, standalone script invocations

**Public API Layer:**
- Purpose: Exposes user-facing lab management commands
- Location: `/mnt/c/projects/AutomatedLab/Public/`
- Contains: 40+ cmdlets for VM lifecycle, networking, domain operations
- Depends on: Private helpers, Hyper-V module, GlobalLabConfig
- Used by: Orchestration layer, GUI event handlers, interactive sessions

**Private Helper Layer:**
- Purpose: Internal utilities and orchestration decision logic
- Location: `/mnt/c/projects/AutomatedLab/Private/`
- Contains: Configuration resolvers, state probes, mode decision engines, validation helpers
- Depends on: GlobalLabConfig, Hyper-V APIs
- Used by: Public commands, orchestration layer

**GUI Layer:**
- Purpose: Provides visual interface for lab management
- Location: `/mnt/c/projects/AutomatedLab/GUI/`
- Contains: WPF views (XAML), theme system, event handlers, visual components
- Depends on: Public API, Private helpers, Lab-Config.ps1
- Used by: End users via GUI mode launch

**Role Provisioning Layer:**
- Purpose: VM role-specific configuration scripts
- Location: `/mnt/c/projects/AutomatedLab/LabBuilder/Roles/`
- Contains: 16 role scripts (DC, SQL, IIS, Ubuntu, etc.)
- Depends on: Hyper-V, VM guest integration
- Used by: Deploy.ps1, VM initialization workflows

**Configuration Layer:**
- Purpose: Centralized lab configuration and defaults
- Location: `/mnt/c/projects/AutomatedLab/Lab-Config.ps1`
- Contains: GlobalLabConfig hashtable with nested sections for Lab, Paths, Credentials, Network, IPPlan
- Depends on: Nothing (config source of truth)
- Used by: All layers

## Data Flow

**Lab Deployment Flow:**

1. User invokes `OpenCodeLab-App.ps1 -Action deploy -Mode quick`
2. Orchestrator loads `Lab-Config.ps1` → GlobalLabConfig hashtable populated
3. Orchestrator sources Private helpers from `$OrchestrationHelperPaths` array
4. `Resolve-LabModeDecision` probes current state via `Get-LabStateProbe`
5. `Get-LabStateProbe` checks: LabRegistered, MissingVMs, LabReadySnapshot, Switch, NAT
6. If quick mode + gaps detected → `Invoke-LabQuickModeHeal` auto-repairs infrastructure
7. Orchestrator calls `Deploy.ps1` with resolved mode and parameters
8. Deploy.ps1 loads template via `Get-ActiveTemplateConfig` from `.planning/templates/`
9. Deploy.ps1 iterates VM definitions, calls `New-LabVM` for each
10. `New-LabVM` → Hyper-V VM creation → VHD provisioning → Unattend.xml injection
11. VMs boot → OS install → domain join via `Join-LabDomain`
12. Role scripts in `LabBuilder/Roles/` execute for DC, SQL, IIS, etc.
13. Final state saved via `Save-LabReadyCheckpoint` for future quick-mode restoration

**State Management:**
- GlobalLabConfig: Loaded once at orchestrator startup from `Lab-Config.ps1`
- State probes: Executed on-demand by decision helpers, return PSCustomObject snapshots
- Snapshots: Hyper-V snapshots used as restore points for quick mode
- Run artifacts: JSON logs written to `.planning-archive/runs/` via `Write-RunArtifact`

**GUI Data Flow:**

1. User launches `Scripts/Run-OpenCodeLab.ps1 -GUI`
2. `GUI/Start-OpenCodeLabGUI.ps1` loads WPF assemblies and XAML files
3. Dot-sources all `/Private/*.ps1` and `/Public/*.ps1` for function availability
4. `Import-XamlFile` loads `MainWindow.xaml` and view XAML files
5. `Switch-View` replaces content area with DashboardView/ActionsView/etc.
6. Dashboard: 5-second timer polls `Get-LabStatus` → updates VM cards + topology canvas
7. Actions: User selects action → `New-LabGuiCommandPreview` builds CLI string → `Start-Process` elevated PowerShell
8. Customize: Template editor reads/writes `.planning/templates/*.json` via `Save-LabTemplate`
9. Settings: GUI settings persist to `.planning/gui-settings.json` via `Save-GuiSettings`
10. Logs: In-memory `$script:LogEntries` list rendered with color-coded WPF Inlines

## Key Abstractions

**GlobalLabConfig:**
- Purpose: Single source of truth for all lab configuration
- Examples: Referenced in `Lab-Config.ps1`, consumed by all Public/Private functions
- Pattern: Hashtable with nested sections (Lab, Paths, Credentials, Network, IPPlan, VMs)

**State Probe:**
- Purpose: Captures current lab infrastructure state for decision logic
- Examples: `Get-LabStateProbe`, `Get-LabFleetStateProbe`
- Pattern: Returns PSCustomObject with boolean flags (LabRegistered, MissingVMs, SwitchPresent, NatPresent, LabReadyAvailable)

**Mode Decision:**
- Purpose: Resolves quick vs. full deployment strategy based on state
- Examples: `Resolve-LabModeDecision` in `/mnt/c/projects/AutomatedLab/Private/Resolve-LabModeDecision.ps1`
- Pattern: Input (RequestedMode + StateProbe) → Output (EffectiveMode + SkipVMs + AutoHeal decision)

**VM Configuration:**
- Purpose: Defines VM specs (IP, memory, processors, role)
- Examples: `Get-LabVMConfig` returns hashtable from `.planning/config.json` VMConfiguration
- Pattern: Hashtable keyed by VM name with Role, MemoryGB, ProcessorCount, IP properties

**Template:**
- Purpose: Reusable VM deployment definitions
- Examples: `.planning/templates/default.json` with VMs array
- Pattern: JSON file with description + array of {name, role, ip, memoryGB, processors}

**Run Artifact:**
- Purpose: Execution trace for debugging and reporting
- Examples: `Write-RunArtifact` writes JSON + TXT to `.planning-archive/runs/`
- Pattern: Timestamped logs with Action, Mode, StartTime, EndTime, Status, Errors

## Entry Points

**CLI Orchestrator:**
- Location: `/mnt/c/projects/AutomatedLab/OpenCodeLab-App.ps1`
- Triggers: Direct execution or via `Scripts/Run-OpenCodeLab.ps1`
- Responsibilities: Validates action, resolves mode, loads config, invokes Deploy/Bootstrap/Teardown, manages confirmation tokens

**GUI Entry Point:**
- Location: `/mnt/c/projects/AutomatedLab/GUI/Start-OpenCodeLabGUI.ps1`
- Triggers: `Scripts/Run-OpenCodeLab.ps1 -GUI`
- Responsibilities: Loads WPF assemblies, sources all functions, initializes theme, shows MainWindow, wires event handlers

**Launcher Script:**
- Location: `/mnt/c/projects/AutomatedLab/Scripts/Run-OpenCodeLab.ps1`
- Triggers: User invocation, supports -GUI switch and -AppArguments passthrough
- Responsibilities: Syntax validation, routes to GUI or CLI orchestrator

**Module Import:**
- Location: `/mnt/c/projects/AutomatedLab/SimpleLab.psm1`
- Triggers: `Import-Module SimpleLab` or auto-import when installed
- Responsibilities: Dot-sources all Private and Public scripts, exports Public functions

**Bootstrap Script:**
- Location: `/mnt/c/projects/AutomatedLab/Bootstrap.ps1`
- Triggers: `OpenCodeLab-App.ps1 -Action bootstrap`
- Responsibilities: Installs prerequisites (Hyper-V, NuGet, Pester), creates directories, downloads ISOs, validates environment

**Deploy Script:**
- Location: `/mnt/c/projects/AutomatedLab/Deploy.ps1`
- Triggers: `OpenCodeLab-App.ps1 -Action deploy` or direct invocation
- Responsibilities: Provisions VMs from template, configures network, joins domain, applies roles, creates checkpoints

## Error Handling

**Strategy:** Structured error objects with fallback paths

**Patterns:**
- Public functions return PSCustomObject with Success/Status/Message properties
- `$ErrorActionPreference = 'Stop'` enforced in orchestrators and critical helpers
- Try/catch blocks wrap Hyper-V cmdlets with context-aware error messages
- Validation gates before destructive operations (confirmation tokens, state probes)
- GUI: MessageBox dialogs for user-facing errors, silent Continue in polling timers
- Orchestrator: Confirmation token validation via `Test-LabScopedConfirmationToken` for blow-away action

## Cross-Cutting Concerns

**Logging:**
- Orchestrator: `Write-Host` with color coding for status messages
- GUI: `Add-LogEntry` writes to in-memory list, rendered to WPF TextBlock with color-coded Inlines
- Run artifacts: JSON + TXT files in `.planning-archive/runs/` via `Write-RunArtifact`

**Validation:**
- Preflight: `Bootstrap.ps1` validates Hyper-V, disk space, ISO availability
- State probes: `Get-LabStateProbe` checks VM existence, snapshots, network infrastructure
- Configuration: `Get-LabConfig`, `Get-LabVMConfig` validate JSON structure
- Network: `Test-LabVirtualSwitchSubnetConflict` prevents IP conflicts
- GUI: Regex validation on IP addresses, template name patterns

**Authentication:**
- Credentials: `Resolve-LabPassword` reads from -AdminPassword param → GlobalLabConfig → env var (OPENCODELAB_ADMIN_PASSWORD)
- SSH keys: `New-LabSSHKey` generates Ed25519 keypairs for Linux VM access
- Domain: Domain admin credentials passed via Invoke-Command -Credential for remote operations

**Configuration Resolution:**
- Centralized: `Lab-Config.ps1` loaded by orchestrator, GUI, Deploy.ps1
- Template system: `.planning/templates/*.json` for VM definitions
- Active template: `.planning/config.json` tracks ActiveTemplate + VMConfiguration
- GUI settings: `.planning/gui-settings.json` for theme and UI preferences
- Precedence: CLI params → GlobalLabConfig → hardcoded defaults

**Module System:**
- Auto-discovery: `Import-LabScriptTree.ps1` recursively finds all .ps1 files in Public/Private
- Dynamic loading: `SimpleLab.psm1` dot-sources discovered files at module load
- Orchestrator helpers: Explicit array `$OrchestrationHelperPaths` in `OpenCodeLab-App.ps1`
- GUI: Sources all Private/Public via `Get-ChildItem` at GUI startup

---

*Architecture analysis: 2026-02-16*
