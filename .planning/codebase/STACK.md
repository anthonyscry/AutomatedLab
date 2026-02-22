# Technology Stack

**Analysis Date:** 2026-02-21

## Languages

**Primary:**
- C# 12 - Windows desktop application (WPF GUI) in `OpenCodeLab-v2/` directory
- PowerShell 5.1+ - Lab automation, deployment scripts, scripting infrastructure (legacy OpenCodeLab)
- XAML - WPF UI definition for GUI components

**Secondary:**
- Bash - Linux VM configuration scripts (`Scripts/Configure-LIN1.sh` in legacy lab)
- JSON - Configuration, settings persistence, inventory, and run artifacts
- PowerShell 7.x - Embedded runtime for cross-platform compatibility (bundled `pwsh/` directory)

## Runtime

**Environment:**
- .NET 8.0 (net8.0-windows) - Modern C# WPF application
- Windows PowerShell 5.1+ (legacy SimpleLab module)
- Hyper-V hypervisor (Windows 10/11 Pro, Enterprise, or Education; Windows Server 2016+)
- Bundled PowerShell 7 runtime for Lab Deployment Service (`pwsh/` directory in application package)

**Package Manager:**
- NuGet (C# dependencies via `.csproj`)
- PowerShellGet (PowerShell modules for legacy SimpleLab)
- No lockfiles (PowerShell modules don't use lockfiles)

## Frameworks

**Core:**
- **WPF (Windows Presentation Foundation)** - GUI framework for OpenCodeLab-v2
  - Assemblies: `PresentationFramework`, `PresentationCore`, `WindowsBase`, `System.Windows.Forms`
  - XAML files: `Views/MainWindow.xaml`, `Views/ActionsView.xaml`, `Views/DashboardView.xaml`, `Views/SettingsView.xaml`, `Views/DeploymentProgressWindow.xaml`
  - Resource themes: `App.xaml` with color brushes and button styles
  - Code-behind: `.xaml.cs` files with event handlers and view logic

- **Hyper-V** - Native Windows hypervisor for VM hosting, networking, snapshot management (both C# and PowerShell)
  - C# integration: `System.Management` WMI queries to `root\virtualization\v2` namespace
  - PowerShell integration: `Hyper-V` module cmdlets

- **System.Management** - Windows Management Instrumentation (WMI) for Hyper-V VM queries and control
  - Used in `Services/HyperVService.cs` for VM lifecycle operations
  - Namespace: `root\virtualization\v2` (Hyper-V v2 WMI)

**Testing:**
- **Pester 5.0+** - PowerShell testing framework (legacy SimpleLab)
  - Config: Programmatic via `New-PesterConfiguration` in `Tests/Run.Tests.ps1`
  - Coverage: XML export to `Tests/coverage.xml`

- **xUnit / MSTest** - Not detected in C# codebase (no test projects found)

**Build/Dev:**
- **MSBuild** - .NET project build system (from `.csproj`)
- **GitHub Actions** - CI/CD pipeline (`.github/workflows/opencodelab-v2-ci.yml`)
  - Runs unit, integration, smoke, and ScriptAnalyzer gates
  - Triggers on: Workflow dispatch, push to OpenCodeLab-v2/**, pull requests
  - Requires Windows runners for Hyper-V smoke tests

## Key Dependencies

**Critical:**
- **System.Management** (v9.0.0) - Windows Management Instrumentation for Hyper-V
  - Used in `Services/HyperVService.cs` to query and control VMs via WMI namespace `root\virtualization\v2`
  - Operations: VM state queries, start/stop/pause/restart, memory/processor inspection, uptime queries
  - Namespace: Hyper-V v2 WMI classes (`Msvm_ComputerSystem` for VM queries, `RequestStateChange` for state transitions)

- **Hyper-V PowerShell Module** - VM and network management (legacy SimpleLab and Deploy-Lab.ps1)
  - Functions: `Get-VM`, `New-VM`, `Get-VMSwitch`, `New-VMSwitch`, `Start-VM`, `Stop-VM`, etc.
  - Bundled with Windows; imported via `Import-Module Hyper-V`

**Infrastructure:**
- **PresentationFramework** - WPF framework core
- **PresentationCore** - WPF rendering engine
- **WindowsBase** - WPF base classes
- **System.Text.Json** - JSON serialization for lab configuration and settings persistence
  - Used in `Services/LabDeploymentService.cs` to serialize/deserialize lab configs
  - File format: `System.Text.Json.JsonSerializerOptions { WriteIndented = true }`

- **System.Diagnostics.Process** - PowerShell subprocess execution via `Process.Start()`
  - Used in `Services/LabDeploymentService.cs` to invoke `Deploy-Lab.ps1` deployment scripts
  - Captures stdout/stderr for logging

- **System.IO** - File operations for deployment, settings persistence, ISO detection
  - Lab sources directory: `C:\LabSources`
  - Log directory: `C:\LabSources\Logs`
  - Settings file: User-configurable path (typically AppData)

- **System.Threading.Tasks** - Asynchronous operations for WPF UI responsiveness
  - ViewModels use async/await patterns for service calls
  - Deployment progress updates via `Progress` event

- **Microsoft.Win32** - Registry access and file dialogs (OpenFileDialog in SettingsViewModel)

**Optional:**
- **Ansible** - Optional automation tooling (legacy SimpleLab)
  - Installation script: `Scripts/Install-Ansible.ps1`
  - Inventory format: JSON with top-level `hosts` array

## Configuration

**Environment:**
- Settings stored in user JSON file: `.planning/gui-settings.json`
  - Theme preference (Dark/Light)
  - Lab paths, ISO paths, network configuration
  - Refresh intervals, log line limits
- Loaded/saved asynchronously by `SettingsViewModel.cs`

- Lab config via `config/lab.settings.psd1` (PowerShell Data File)
  - Lab name, artifact log root paths
  - Dynamically loaded by `opencodelab.ps1` launcher

- Password/secrets via environment variables:
  - `OPENCODELAB_ADMIN_PASSWORD` - Admin password for lab operations
  - `LAB_ADMIN_PASSWORD` - LabBuilder password override
  - `OPENCODELAB_DISPATCH_MODE` - Dispatcher execution mode (off|canary|enforced)

**Build:**
- Project file: `OpenCodeLab-V2.csproj`
  - OutputType: WinExe (Windows executable)
  - TargetFramework: net8.0-windows
  - Nullable: enabled (C# null safety)
  - UseWPF: true
  - SelfContained: true (no separate .NET runtime install needed)
  - RuntimeIdentifier: win-x64
  - ApplicationManifest: `app.manifest` - UAC elevation for administrator privileges

- `app.manifest` - Assembly manifest with `requestedExecutionLevel="requireAdministrator"`
- `Deploy-Lab.ps1` - PowerShell deployment orchestration script bundled with executable

**Data Formats:**
- **JSON** - Settings persistence (`.planning/gui-settings.json`), lab configurations, VM definitions
- **XAML** - WPF UI definitions and themes (`App.xaml`, `Views/*.xaml`)
- **PowerShell Data File (.psd1)** - Lab configuration (`config/lab.settings.psd1`)
- **TXT** - Run logs in `artifacts/logs/` directories

## Platform Requirements

**Development:**
- Windows 10/11 Pro/Enterprise or Windows Server 2016+
- .NET 8.0 SDK
- Visual Studio 2022+ or JetBrains Rider (C# IDE)
- PowerShell 5.1+ (for scripting infrastructure)
- Hyper-V enabled on development machine (for integration testing)
- Administrator privileges for Hyper-V operations

**Production/Runtime:**
- Windows 10/11 Pro/Enterprise or Windows Server 2016+
- Hyper-V role/feature enabled
- Administrator/elevated privileges required (enforced via `app.manifest`)
- .NET 8.0 runtime (embedded in self-contained build)
- C:\LabSources directory structure must exist:
  - `C:\LabSources\ISOs\` - Windows/Linux ISO images
  - `C:\LabSources\Logs\` - Application logs and crash dumps
  - `C:\AutomatedLab\` - Lab VM storage (default)
- 16 GB+ RAM, fast SSD storage (100 GB+ free) strongly recommended for multi-VM hosting

**Deployment:**
- Lab network: Hyper-V internal switch + NAT (default: `10.0.10.0/24`)
- Lab storage: `C:\AutomatedLab\` (VM files, snapshots)
- Lab sources: `C:\LabSources\` (ISOs, scripts, logs)
- Lab share: `C:\LabShare\` (SMB share for guest access)

---

*Stack analysis: 2026-02-21*
