# Codebase Structure

**Analysis Date:** 2026-02-16

## Directory Layout

```
/mnt/c/projects/AutomatedLab/
├── .planning/                    # Planning artifacts and GUI settings
│   ├── codebase/                 # Codebase analysis docs (this file)
│   ├── templates/                # VM deployment templates (JSON)
│   ├── config.json               # Active template and VM configuration
│   └── gui-settings.json         # GUI theme and preferences
├── .planning-archive/            # Archived planning docs and run logs
│   └── runs/                     # Execution artifacts (JSON + TXT)
├── Private/                      # Internal helper functions (57 files)
│   └── Linux/                    # Linux-specific helpers
├── Public/                       # Exported module commands (50 files)
│   └── Linux/                    # Linux VM management commands
├── GUI/                          # WPF GUI components
│   ├── Components/               # Reusable XAML components (VMCard.xaml)
│   ├── Themes/                   # Dark.xaml, Light.xaml
│   ├── Views/                    # DashboardView, ActionsView, etc. (5 XAML files)
│   ├── MainWindow.xaml           # Main window layout
│   └── Start-OpenCodeLabGUI.ps1  # GUI entry point
├── Scripts/                      # Launcher and utility scripts
│   └── Run-OpenCodeLab.ps1       # Build check + app launcher
├── LabBuilder/                   # Role provisioning system
│   ├── Config/                   # LabDefaults.psd1
│   ├── Roles/                    # 16 role scripts (DC, SQL, IIS, Ubuntu, etc.)
│   └── Logs/                     # Role execution logs
├── Tests/                        # Pester test suites
│   └── results/                  # Test output artifacts
├── docs/                         # Documentation
│   └── plans/                    # Planning documents
├── Ansible/                      # Ansible playbooks for Linux config
│   └── playbooks/
├── OpenCodeLab-App.ps1           # CLI orchestrator entry point
├── Bootstrap.ps1                 # One-click setup script
├── Deploy.ps1                    # VM deployment script
├── Lab-Config.ps1                # Global configuration (GlobalLabConfig)
├── Lab-Common.ps1                # Shared utility functions
├── SimpleLab.psm1                # PowerShell module manifest
├── SimpleLab.psd1                # Module metadata
└── run-lab.ps1                   # Quick launcher alias
```

## Directory Purposes

**.planning/**
- Purpose: Runtime state, configuration, and GUI preferences
- Contains: JSON files for templates, active config, GUI settings
- Key files: `config.json` (ActiveTemplate + VMConfiguration), `gui-settings.json` (Theme)

**.planning-archive/**
- Purpose: Historical run logs and archived planning documents
- Contains: Timestamped execution artifacts in `runs/`, phase planning in `phases/`
- Key files: Run artifacts in JSON + TXT format with Action, Mode, Status, Errors

**Private/**
- Purpose: Internal helper functions not exposed to end users
- Contains: 57 .ps1 files including orchestration helpers, state probes, mode decision logic
- Key files: `Get-LabStateProbe.ps1`, `Resolve-LabModeDecision.ps1`, `Invoke-LabQuickModeHeal.ps1`, `Import-LabScriptTree.ps1`

**Private/Linux/**
- Purpose: Linux VM-specific internal helpers
- Contains: SSH utilities, file copy, DHCP lease detection
- Key files: `Invoke-LinuxSSH.ps1`, `Copy-LinuxFile.ps1`, `Get-LinuxVMDhcpLeaseIPv4.ps1`

**Public/**
- Purpose: User-facing lab management commands (exported by SimpleLab module)
- Contains: 50 .ps1 files for VM lifecycle, networking, domain, snapshots
- Key files: `Get-LabStatus.ps1`, `Initialize-LabVMs.ps1`, `New-LabVM.ps1`, `Save-LabReadyCheckpoint.ps1`

**Public/Linux/**
- Purpose: Linux VM management commands
- Contains: Linux VM creation, SSH management, domain join utilities
- Key files: `New-LinuxVM.ps1`, `New-LinuxGoldenVhdx.ps1`, `Join-LinuxToDomain.ps1`

**GUI/**
- Purpose: WPF graphical user interface
- Contains: XAML files, PowerShell event handlers, view initialization logic
- Key files: `Start-OpenCodeLabGUI.ps1`, `MainWindow.xaml`

**GUI/Components/**
- Purpose: Reusable XAML UI components
- Contains: `VMCard.xaml` (VM status card template)

**GUI/Themes/**
- Purpose: Theme resource dictionaries
- Contains: `Dark.xaml`, `Light.xaml` with brush definitions

**GUI/Views/**
- Purpose: Main content area views
- Contains: `DashboardView.xaml`, `ActionsView.xaml`, `CustomizeView.xaml`, `LogsView.xaml`, `SettingsView.xaml`

**Scripts/**
- Purpose: Launcher and build utility scripts
- Contains: `Run-OpenCodeLab.ps1` (validates syntax, routes to GUI or CLI)

**LabBuilder/Roles/**
- Purpose: VM role-specific provisioning scripts
- Contains: 16 .ps1 files (DC.ps1, SQL.ps1, IIS.ps1, Ubuntu.ps1, Docker.Ubuntu.ps1, K8s.Ubuntu.ps1, etc.)

**LabBuilder/Config/**
- Purpose: Default lab configuration values
- Contains: `LabDefaults.psd1` (fallback values for VM specs)

**Tests/**
- Purpose: Pester 5.x test suites
- Contains: 40+ test files covering orchestration, coordinators, mode decisions, GUI helpers
- Key files: `CoordinatorIntegration.Tests.ps1`, `DeployModeHandoff.Tests.ps1`, `QuickModeHeal.Tests.ps1`

**docs/**
- Purpose: User and developer documentation
- Contains: Architecture docs, smoke test checklists, planning docs
- Key files: `ARCHITECTURE.md`, `SMOKE-CHECKLIST.md`, `REPOSITORY-STRUCTURE.md`

**Ansible/**
- Purpose: Configuration management for Linux VMs
- Contains: Playbooks for post-deployment Linux configuration

## Key File Locations

**Entry Points:**
- `/mnt/c/projects/AutomatedLab/OpenCodeLab-App.ps1`: CLI orchestrator (main app entry point)
- `/mnt/c/projects/AutomatedLab/GUI/Start-OpenCodeLabGUI.ps1`: GUI entry point
- `/mnt/c/projects/AutomatedLab/Scripts/Run-OpenCodeLab.ps1`: Launcher with -GUI switch support
- `/mnt/c/projects/AutomatedLab/SimpleLab.psm1`: PowerShell module entry point

**Configuration:**
- `/mnt/c/projects/AutomatedLab/Lab-Config.ps1`: Global configuration (GlobalLabConfig hashtable)
- `/mnt/c/projects/AutomatedLab/SimpleLab.psd1`: PowerShell module manifest
- `/mnt/c/projects/AutomatedLab/.planning/config.json`: Active template and VMConfiguration
- `/mnt/c/projects/AutomatedLab/.planning/gui-settings.json`: GUI preferences (theme)
- `/mnt/c/projects/AutomatedLab/LabBuilder/Config/LabDefaults.psd1`: Default VM specs

**Core Logic:**
- `/mnt/c/projects/AutomatedLab/Deploy.ps1`: VM deployment orchestration
- `/mnt/c/projects/AutomatedLab/Bootstrap.ps1`: Environment setup and prerequisite installation
- `/mnt/c/projects/AutomatedLab/Lab-Common.ps1`: Shared utility functions

**Testing:**
- `/mnt/c/projects/AutomatedLab/Tests/*.Tests.ps1`: Pester 5.x test suites
- `/mnt/c/projects/AutomatedLab/Tests/results/`: Test output artifacts
- `/mnt/c/projects/AutomatedLab/testResults.xml`: Pester test results XML

## Naming Conventions

**Files:**
- PowerShell scripts: `PascalCase` with verb-noun pattern (e.g., `Get-LabStatus.ps1`, `Invoke-LabQuickModeHeal.ps1`)
- XAML views: `PascalCaseView.xaml` (e.g., `DashboardView.xaml`, `ActionsView.xaml`)
- XAML components: `PascalCase.xaml` (e.g., `VMCard.xaml`, `MainWindow.xaml`)
- Configuration files: `PascalCase-Purpose.ps1` or `lowercase.json` (e.g., `Lab-Config.ps1`, `config.json`)
- Test files: `Feature.Tests.ps1` (e.g., `CoordinatorIntegration.Tests.ps1`, `QuickModeHeal.Tests.ps1`)

**Directories:**
- Module folders: `PascalCase` (e.g., `Private`, `Public`, `Tests`)
- Feature areas: `PascalCase` (e.g., `LabBuilder`, `Scripts`, `Ansible`)
- Hidden/meta: `.lowercase` (e.g., `.planning`, `.planning-archive`)

**Functions:**
- Public: `Verb-LabNoun` (e.g., `Get-LabStatus`, `New-LabVM`, `Initialize-LabVMs`)
- Private: `Verb-LabNoun` or `Verb-Purpose` (e.g., `Resolve-LabModeDecision`, `ConvertTo-LabTargetHostList`)
- Internal helpers: `Verb-Purpose` (e.g., `Ensure-VMRunning`, `Test-DiskSpace`)

## Where to Add New Code

**New Public Command:**
- Primary code: `/mnt/c/projects/AutomatedLab/Public/YourCommand.ps1`
- Tests: `/mnt/c/projects/AutomatedLab/Tests/YourCommand.Tests.ps1`
- Export: Add function name to `Export-ModuleMember -Function @(...)` in `/mnt/c/projects/AutomatedLab/SimpleLab.psm1`

**New Private Helper:**
- Implementation: `/mnt/c/projects/AutomatedLab/Private/YourHelper.ps1`
- If used by orchestrator: Add path to `$OrchestrationHelperPaths` array in `/mnt/c/projects/AutomatedLab/OpenCodeLab-App.ps1`
- Auto-discovered by module: No changes needed to `SimpleLab.psm1` (uses `Import-LabScriptTree.ps1`)

**New GUI View:**
- XAML layout: `/mnt/c/projects/AutomatedLab/GUI/Views/YourView.xaml`
- Initialization function: Add `Initialize-YourView` function to `/mnt/c/projects/AutomatedLab/GUI/Start-OpenCodeLabGUI.ps1`
- Navigation: Add button to `MainWindow.xaml` and wire `Switch-View -ViewName 'Your'` handler

**New VM Role:**
- Implementation: `/mnt/c/projects/AutomatedLab/LabBuilder/Roles/YourRole.ps1`
- Template integration: Add role name to available roles in `GUI/Start-OpenCodeLabGUI.ps1` (CustomizeView initialization)
- Deployment: Reference role in template JSON or call from `Deploy.ps1` workflow

**New Orchestration Helper:**
- Implementation: `/mnt/c/projects/AutomatedLab/Private/YourHelper.ps1`
- Registration: Add full path to `$OrchestrationHelperPaths` array in `/mnt/c/projects/AutomatedLab/OpenCodeLab-App.ps1` (lines 69-88)
- Pattern: Use `[CmdletBinding()]` and return PSCustomObject

**New Test Suite:**
- Test file: `/mnt/c/projects/AutomatedLab/Tests/YourFeature.Tests.ps1`
- Pattern: Use Pester 5.x syntax with `Describe`, `Context`, `It`, `BeforeAll`, `BeforeEach`
- Run: `Invoke-Pester -Path Tests/YourFeature.Tests.ps1`

## Special Directories

**.planning/**
- Purpose: Runtime configuration and GUI state
- Generated: No (manually maintained JSON files)
- Committed: Yes (config.json for ActiveTemplate, gui-settings.json ignored)

**.planning-archive/**
- Purpose: Execution logs and archived planning documents
- Generated: Yes (run artifacts created by `Write-RunArtifact`)
- Committed: No (.gitignore excludes runs/)

**.planning-archive/runs/**
- Purpose: Timestamped execution artifacts
- Generated: Yes (each action creates JSON + TXT with timestamp)
- Committed: No

**LabBuilder/Logs/**
- Purpose: Role script execution logs
- Generated: Yes (role scripts write logs during provisioning)
- Committed: No

**Tests/results/**
- Purpose: Pester test output artifacts
- Generated: Yes (test runs create XML and coverage reports)
- Committed: No

**.git/**
- Purpose: Git version control metadata
- Generated: Yes (by git operations)
- Committed: No (git internals)

**.archive/**
- Purpose: Deprecated code and old implementations
- Generated: No (manually moved obsolete code)
- Committed: Yes (historical reference)

**.tools/**
- Purpose: Development tooling (PowerShell LSP, analyzers)
- Generated: No (manually installed tools)
- Committed: Yes (for consistent dev environment)

**.claude/**
- Purpose: Claude Code project configuration
- Generated: No (manually configured)
- Committed: Yes

**.opencode/**
- Purpose: OpenCode CLI custom commands
- Generated: No (manually created extensions)
- Committed: Yes

**docs/plans/**
- Purpose: Feature planning documents
- Generated: No (manually written planning docs)
- Committed: Yes

## File Discovery Patterns

**Module Auto-Loading:**
- Mechanism: `SimpleLab.psm1` calls `Import-LabScriptTree.ps1` → `Get-LabScriptFiles`
- Pattern: Recursively finds all `*.ps1` files in `Private/` and `Public/`
- Exclusions: `Import-LabScriptTree.ps1` excluded from Private loading
- Result: All discovered files dot-sourced at module import time

**Orchestrator Helpers:**
- Mechanism: Explicit array `$OrchestrationHelperPaths` in `OpenCodeLab-App.ps1`
- Pattern: Hardcoded paths to specific helpers (17 files)
- Loading: `foreach` loop dot-sources each path if file exists
- Purpose: Ensures critical helpers available before orchestration logic runs

**GUI Function Loading:**
- Mechanism: `Start-OpenCodeLabGUI.ps1` uses `Get-ChildItem` on `Private/` and `Public/`
- Pattern: Dot-sources all `*.ps1` files recursively
- Result: All lab functions available to GUI event handlers

**XAML Loading:**
- Mechanism: `Import-XamlFile` function reads .xaml files and parses via XamlReader
- Pattern: `Import-XamlFile -Path (Join-Path $GuiRoot 'Views/DashboardView.xaml')`
- Result: WPF object tree loaded into PowerShell variables

**Template Discovery:**
- Mechanism: `Get-ChildItem -Path .planning/templates -Filter *.json`
- Pattern: JSON files in templates directory enumerated at runtime
- Result: ComboBox populated with available templates in CustomizeView

---

*Structure analysis: 2026-02-16*
