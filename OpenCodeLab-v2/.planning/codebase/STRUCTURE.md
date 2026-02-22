# Codebase Structure

**Analysis Date:** 2025-02-21

## Directory Layout

```
OpenCodeLab-v2/
├── src/                            # PowerShell modules
│   ├── OpenCodeLab.App/            # CLI orchestration entry point
│   ├── OpenCodeLab.Core/           # Foundational utilities
│   │   └── Public/                 # Exported functions
│   ├── OpenCodeLab.Domain/         # Lab actions and state logic
│   │   ├── Actions/                # Lab operation handlers
│   │   ├── Policy/                 # Policy decision functions
│   │   ├── State/                  # State machine definitions
│   │   └── Public/                 # Utilities
│   ├── OpenCodeLab.Infrastructure.HyperV/  # Platform abstraction
│   │   └── Public/                 # Hyper-V wrappers
│   └── OpenCodeLab.Presentation.Console/   # Text output formatting
│       └── Public/                 # Console presentation
├── scripts/                        # Entry point launchers
│   └── opencodelab.ps1             # CLI launcher
├── Views/                          # WPF XAML views
│   ├── MainWindow.xaml             # Main application window
│   ├── ActionsView.xaml            # Lab deployment UI
│   ├── DashboardView.xaml          # Lab status display
│   ├── SettingsView.xaml           # Configuration UI
│   ├── NewLabDialog.xaml           # Lab creation dialog
│   ├── DeploymentProgressWindow.xaml
│   └── *.xaml.cs                   # Code-behind
├── ViewModels/                     # MVVM ViewModels
│   ├── ActionsViewModel.cs         # Actions tab logic
│   ├── DashboardViewModel.cs       # Dashboard tab logic
│   ├── SettingsViewModel.cs        # Settings tab logic
│   ├── AsyncCommand.cs             # ICommand implementation for async
│   └── ObservableObject.cs         # INotifyPropertyChanged base
├── Services/                       # C# service layer
│   ├── LabDeploymentService.cs     # Lab deployment orchestration
│   └── HyperVService.cs            # Hyper-V API wrapper
├── Models/                         # C# data models
│   ├── LabConfig.cs                # Lab configuration class
│   └── VirtualMachine.cs           # VM definition class
├── config/                         # Configuration files
│   └── lab.settings.psd1           # Default PowerShell config
├── artifacts/                      # Runtime outputs
│   ├── logs/                       # Execution artifacts (generated)
│   │   ├── {RunId}/                # Per-run directory
│   │   │   ├── run.json            # Complete result object
│   │   │   ├── summary.txt         # Text summary
│   │   │   ├── errors.json         # Error details (if failed)
│   │   │   └── events.jsonl        # Event log (one JSON per line)
│   │   └── run.lock                # Mutex lock file
│   └── publish/                    # Distribution artifacts
├── tests/                          # Test suites
│   ├── unit/                       # Unit tests
│   ├── integration/                # Integration tests
│   └── smoke/                      # Smoke tests
├── pwsh/                           # Embedded PowerShell 7 runtime
├── App.xaml.cs                     # WPF application entry
├── App.xaml                        # WPF resource definitions
├── OpenCodeLab-V2.csproj           # C# project file
├── OpenCodeLab-V2.exe              # Compiled application
└── Deploy-Lab.ps1                  # Lab deployment script (at project root)
```

## Directory Purposes

**`src/OpenCodeLab.App/`:**
- Purpose: CLI application orchestration entry point
- Contains: Module manifest (.psd1), root module (.psm1) with public functions
- Key files: `OpenCodeLab.App.psd1` (exports: Get-LabCommandMap, Invoke-LabCliCommand, Resolve-LabExitCode)
- Module dynamically dots-sources all required dependencies at load time

**`src/OpenCodeLab.Core/Public/`:**
- Purpose: Foundational utilities shared across all layers
- Contains: Configuration, locking, artifact, and event management functions
- Key patterns: All functions use `[CmdletBinding()]`, return typed objects, validate inputs
- No dependencies on other custom modules

**`src/OpenCodeLab.Domain/Actions/`:**
- Purpose: Implement each user-facing action (deploy, teardown, preflight, etc.)
- Contains: Five action handlers: `Invoke-LabDeployAction`, `Invoke-LabTeardownAction`, `Invoke-LabPreflightAction`, `Invoke-LabStatusAction`, `Invoke-LabHealthAction`
- Each follows pattern: Validate input → Acquire lock → Execute logic → Handle errors → Return standardized result

**`src/OpenCodeLab.Domain/State/`:**
- Purpose: Define deployment orchestration state machine
- Contains: `Invoke-LabDeployStateMachine` (currently returns static steps list, expandable for complex workflows)

**`src/OpenCodeLab.Domain/Policy/`:**
- Purpose: Implement conditional logic for lab operations
- Contains: `Resolve-LabTeardownPolicy` (decides if teardown is allowed based on state)

**`src/OpenCodeLab.Infrastructure.HyperV/Public/`:**
- Purpose: Abstract Hyper-V platform operations
- Contains: `Test-HyperVPrereqs` (checks if Hyper-V is available), `Get-LabVmSnapshot` (queries VM snapshots)
- Isolated from domain logic for testability and future platform swapping

**`Views/`:**
- Purpose: WPF XAML view definitions
- Contains: Grid-based layouts, data bindings, command bindings
- Key views:
  - `MainWindow.xaml`: Tab container (Dashboard, Actions, Settings)
  - `ActionsView.xaml`: Lab list, deployment controls, log output
  - `DashboardView.xaml`: VM cards, network topology, status indicators
  - `SettingsView.xaml`: Configuration options, theme selection
  - `NewLabDialog.xaml`: Lab creation form with VM/network fields

**`ViewModels/`:**
- Purpose: Implement MVVM pattern, manage UI state and commands
- Contains: One ViewModel per major view section
- Pattern: Inherit from `ObservableObject`, expose `ICommand` properties, use `AsyncCommand` for async operations
- Update cycle: UI triggers command → ViewModel executes async method → ViewModel properties updated → UI refreshes

**`Services/`:**
- Purpose: Bridge between WPF and PowerShell backend
- `LabDeploymentService`: Finds Deploy-Lab.ps1, spawns PowerShell process, streams output, parses progress events
- `HyperVService`: Uses WMI/System.Management to query VM state, memory, CPU without spawning processes

**`Models/`:**
- Purpose: Strongly-typed data objects for WPF and deployment
- `LabConfig`: Contains LabName, LabPath, Description, Network (SwitchName, SwitchType, IPPrefix, VLAN), VMs list
- `VMDefinition`: Name, Role, MemoryGB, Processors, SwitchName, IPAddress, SubnetMask, Gateway, DNS, ISOPath, DiskSizeGB

**`config/`:**
- Purpose: Store application configuration in PowerShell Data Format
- `lab.settings.psd1`: Lab name, paths (especially LogRoot which can be absolute or relative to config file)
- Format: Hashtable with nested sections (Lab, Paths)

**`artifacts/logs/`:**
- Purpose: Store execution artifacts and logs
- Generated automatically on first run
- Each run creates: `{RunId}/` directory with run.json, summary.txt, errors.json, events.jsonl
- `run.lock` file prevents concurrent execution (mutex)

**`tests/`:**
- Purpose: Test coverage organized by type
- `unit/`: Function-level tests with mocked dependencies
- `integration/`: Tests that execute actual PowerShell modules
- `smoke/`: Quick sanity check tests (run before merge)

**`pwsh/`:**
- Purpose: Embedded PowerShell 7 runtime bundled with WPF app
- Auto-copied to output on build via CopyToOutputDirectory directive
- Allows deployment on machines without PowerShell 7 installed

## Key File Locations

**Entry Points:**
- `scripts/opencodelab.ps1`: CLI entry point (imports module, calls Invoke-LabCliCommand)
- `App.xaml.cs` + `App.xaml`: WPF application initialization
- `Views/MainWindow.xaml`: Main UI window container

**Configuration:**
- `config/lab.settings.psd1`: Lab configuration template
- `OpenCodeLab-V2.csproj`: C# build configuration, output type, package references
- `app.manifest`: Windows privilege escalation (admin required)

**Core Logic:**
- `src/OpenCodeLab.App/OpenCodeLab.App.psm1`: Command dispatch and result orchestration
- `src/OpenCodeLab.Domain/Actions/Invoke-Lab*Action.ps1`: Action implementations
- `src/OpenCodeLab.Domain/State/Invoke-LabDeployStateMachine.ps1`: Deployment orchestration
- `Services/LabDeploymentService.cs`: WPF service for deployment execution

**Testing:**
- `tests/unit/`: PowerShell Pester tests for module functions
- `tests/integration/`: End-to-end tests including external dependencies
- `tests/smoke/`: Quick checks for regression

**Artifact Output:**
- `artifacts/logs/{RunId}/run.json`: Complete execution result
- `artifacts/logs/{RunId}/events.jsonl`: Event stream (one JSON object per line)
- `artifacts/logs/run.lock`: Mutex file (binary content, not human-readable)

## Naming Conventions

**Files:**
- PowerShell actions: `Invoke-Lab<Action>Action.ps1` (e.g., Invoke-LabDeployAction.ps1)
- PowerShell utilities: `<Verb>-Lab<Noun>.ps1` (e.g., Enter-LabRunLock.ps1)
- C# classes: PascalCase, no suffix (e.g., LabDeploymentService.cs, ActionsViewModel.cs)
- XAML views: PascalCase with View/Window suffix (e.g., ActionsView.xaml, MainWindow.xaml)
- Manifest files: `<Module>.psd1` (e.g., OpenCodeLab.App.psd1)
- Module roots: `<Module>.psm1` (e.g., OpenCodeLab.App.psm1)

**Directories:**
- PowerShell modules: `OpenCodeLab.<Layer>` (e.g., OpenCodeLab.Core, OpenCodeLab.Domain)
- Subdirectories by concern: `Public/` (exported), `Private/` (internal), by feature (Actions/, State/, Policy/)
- C# folders: Plural for collections (Views/, ViewModels/, Models/, Services/)

**Functions/Methods:**
- PowerShell functions: PascalCase Verb-Noun (e.g., Enter-LabRunLock, Invoke-LabDeployAction)
- C# methods: PascalCase with Async suffix for async methods (e.g., DeployLabAsync, RemoveLabAsync)
- C# properties: PascalCase (e.g., IsDeploying, LogOutput, DeploymentProgress)

**Classes/Types:**
- C# classes: PascalCase (e.g., LabDeploymentService, ActionsViewModel, LabConfig)
- PowerShell custom objects: Implicit via [pscustomobject]

## Where to Add New Code

**New Action (e.g., Clean-Lab):**
- Create: `src/OpenCodeLab.Domain/Actions/Invoke-LabCleanAction.ps1`
- Pattern: Match existing action signature (Mode, LockPath params, return LabActionResult)
- Register: Add to command map in `src/OpenCodeLab.App/OpenCodeLab.App.psm1` (Get-LabCommandMap)
- Test: Create `tests/unit/Actions/` test file with Pester tests

**New Utility Function:**
- Location: Depends on layer
  - Core utilities (config, locking, artifacts): `src/OpenCodeLab.Core/Public/`
  - Domain-specific helpers: `src/OpenCodeLab.Domain/Public/`
  - Infrastructure/Hyper-V: `src/OpenCodeLab.Infrastructure.HyperV/Public/`
- Pattern: Use `[CmdletBinding()]`, return typed objects, validate inputs

**New WPF View:**
- Create: `Views/MyFeatureView.xaml` + `Views/MyFeatureView.xaml.cs`
- Create: `ViewModels/MyFeatureViewModel.cs` (inherit from ObservableObject)
- Register: Add tab to `Views/MainWindow.xaml`
- Bind: Set DataContext in code-behind or XAML

**New Service:**
- Create: `Services/MyService.cs`
- Pattern: Public methods that return Task<T> or use event callbacks
- Register: Instantiate in ViewModel that uses it

**New Model:**
- Create: `Models/MyModel.cs`
- Pattern: Auto-properties with public getters/setters
- Use: ViewModel collections and service parameters

**New Test:**
- Unit: `tests/unit/<Layer>/<Feature>.Tests.ps1` (Pester format)
- Integration: `tests/integration/<Feature>.Tests.ps1`
- WPF/C#: `tests/unit/<Class>.Tests.cs` (xUnit/NUnit, if added)

## Special Directories

**`.planning/`:**
- Purpose: Stores GSD planning documents and codebase analysis
- Generated: Not committed initially, written by GSD map-codebase
- Committed: Updated copies checked in with each phase

**`bin/` and `obj/`:**
- Purpose: Build outputs (compiled DLLs, PDBs, intermediate files)
- Generated: Build process creates automatically
- Committed: Not committed (in .gitignore)

**`artifacts/logs/`:**
- Purpose: Runtime execution artifacts
- Generated: Created on first action execution
- Committed: Not committed (ephemeral per environment)

**`.github/`:**
- Purpose: GitHub-specific configuration (workflows, issue templates)
- Committed: Yes (repository configuration)

---

*Structure analysis: 2025-02-21*
