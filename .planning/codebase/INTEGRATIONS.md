# External Integrations

**Analysis Date:** 2026-02-21

## APIs & External Services

**Windows/System:**
- **Hyper-V WMI API** - Virtual machine lifecycle and monitoring
  - SDK/Client: `System.Management` (v9.0.0)
  - Namespace: `root\virtualization\v2`
  - Classes: `Msvm_ComputerSystem` (VM queries), `Msvm_VirtualEthernetSwitch` (network)
  - Implementation: `Services/HyperVService.cs` - VM state queries, power operations, resource inspection
  - Operations: Start/Stop/Pause/Restart VMs, get memory/processor counts, get uptime via WMI
  - Connection method: `ManagementObjectSearcher` with WMI queries

- **Hyper-V PowerShell Module** - VM and vSwitch management
  - Used in: `Deploy-Lab.ps1`, removal operations
  - Functions: `Get-VMSwitch`, `New-VMSwitch`, `Get-VM`, `New-VM`, `Stop-VM`, `Start-VM`, `Remove-VM`
  - Import: `Import-Module Hyper-V -ErrorAction Stop`

- **Windows File Dialog** - File/folder selection
  - Implementation: `Microsoft.Win32.OpenFileDialog` in `SettingsViewModel.cs`
  - Used for: Lab path, ISO path, settings file selection

**PowerShell Scripting Runtime:**
- **PowerShell 7.x Engine** - Bundled in `pwsh/` directory
  - Execution: `LabDeploymentService.cs` spawns PowerShell subprocess via `Process.Start()`
  - Command execution: `-Command` parameter passing
  - Working directory: Lab sources or deployment path

## Data Storage

**Databases:**
- None detected in OpenCodeLab-v2 C# application
- SQL Server (optional) - Installable via legacy LabBuilder templates for full lab environment

**File Storage:**
- **Local filesystem only**
  - Lab sources: `C:\LabSources\ISOs\` - Windows/Linux ISO images
  - Lab logs: `C:\LabSources\Logs\` - Application crash logs, run artifacts
  - Lab storage: `C:\AutomatedLab\` (configurable) - VM virtual disk files (.vhdx)
  - User settings: `.planning/gui-settings.json` - Theme and lab configuration
  - Lab configuration: `.planning/config.json` - Active template selection
  - Lab working directory: Configurable via Settings view (default from `DefaultLabPath` setting)

- **Guest storage**: Dynamic VHDX files attached to Hyper-V VMs

**Configuration Files:**
- `config/lab.settings.psd1` - Lab name, artifact log root (PowerShell Data File)
- Lab configuration JSON files - Lab metadata: name, path, description, domain, network settings, VM definitions

**Settings Persistence:**
- JSON serialization via `System.Text.Json`
- File: `.planning/gui-settings.json`
- Model: `AppSettings` class in `SettingsViewModel.cs`
- Loaded/saved asynchronously by SettingsViewModel
- Properties: DefaultLabPath, LabConfigPath, ISOPath, DefaultSwitchName, DefaultSwitchType, EnableAutoStart, RefreshIntervalSeconds, MaxLogLines

**Caching:**
- None detected

## Authentication & Identity

**Auth Provider:**
- Custom - Windows credentials (implicit)
- Application runs with current user's Windows identity
- Administrative privileges required (enforced via `app.manifest` with `requestedExecutionLevel="requireAdministrator"`)

- **Active Directory Domain Services** (legacy lab) - Local domain controller
  - Domain: `simplelab.local` (default per `Lab-Config.ps1`)
  - DC VM: `DC1` at `10.0.10.10`
  - Admin user: `admin` (configurable)
  - Admin password: Environment variable `OPENCODELAB_ADMIN_PASSWORD` or fallback from `Lab-Config.ps1`

**Password Management:**
- Environment variables (preferred):
  - `OPENCODELAB_ADMIN_PASSWORD` - Admin password for lab operations
  - `LAB_ADMIN_PASSWORD` - LabBuilder password override
- Fallback to hardcoded defaults in scripts (not recommended)

## Monitoring & Observability

**Error Tracking:**
- Local file logging only
- Unhandled exception handler in `App.xaml.cs`
- Exception details logged to `C:\LabSources\Logs\crash-{timestamp}.log`
- Log content: message, stack trace, inner exception details, timestamp

**Logs:**
- Application crash logs: `C:\LabSources\Logs\crash-*.log` (written by exception handler)
- Lab run artifacts: `C:\AutomatedLab\<LabName>\run-logs\` - deployment logs, action outputs
- Settings: `.planning/gui-settings.json` and `config/lab.settings.psd1`
- No centralized logging (ELK, Datadog, etc.)

**Progress Reporting:**
- Event-based: `LabDeploymentService` fires `Progress` event with `DeploymentProgressArgs`
- UI binding: `ActionsViewModel` subscribes to progress updates, updates `DeploymentStatus` property
- Progress steps: 0%, 5%, 10%, 20%, 100% completion

## CI/CD & Deployment

**Hosting:**
- None - desktop application (Windows EXE)
- Distribution: Self-contained `.exe` executable or MSI installer
- Deployment: Single-file or multi-file self-contained build

**CI Pipeline:**
- GitHub Actions (`.github/workflows/opencodelab-v2-ci.yml`)
  - Triggers: Workflow dispatch, push to `OpenCodeLab-v2/**`, pull requests
  - Quality gates:
    - Pester unit tests (`OpenCodeLab-v2/tests/unit`)
    - Pester integration tests (`OpenCodeLab-v2/tests/integration`)
    - Pester smoke tests (`OpenCodeLab-v2/tests/smoke`) - skipped if Hyper-V unavailable
    - PSScriptAnalyzer linting (error and warning severity)
  - Run environment: Windows runners (for Hyper-V support)

**Build Artifacts:**
- Self-contained executable: `OpenCodeLab-V2.exe` (win-x64)
  - Size: ~162 MB (includes .NET runtime, assemblies, bundled PowerShell)
  - Output: `bin/Release/net8.0-windows/win-x64/`

- MSI installer: `OpenCodeLab.msi` (Windows installer package)
  - Size: ~18 GB bundled version
  - Output: `bin/Release/net8.0-windows/win-x64/`

- Program Database: `OpenCodeLab-V2.pdb` (debug symbols)

## Environment Configuration

**Required env vars:**
- None for GUI operation
- Optional for lab deployment:
  - `OPENCODELAB_ADMIN_PASSWORD` - Admin password for lab operations
  - `LAB_ADMIN_PASSWORD` - LabBuilder password override

**Secrets location:**
- Environment variables (preferred)
- No secrets detected in code or config files

**Configuration Discovery:**
- Lab settings loaded from `.planning/gui-settings.json` at startup
- Theme preference (Dark/Light)
- Lab paths: DefaultLabPath, LabConfigPath, ISOPath
- Network: DefaultSwitchName, DefaultSwitchType
- Behavior: EnableAutoStart, RefreshIntervalSeconds, MaxLogLines
- Defaults: Domain = "contoso.com", SwitchName = "LabSwitch", SwitchType = "Internal"

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- None detected

## Remote Execution

**PowerShell Script Execution:**
- **LabDeploymentService.cs** - Subprocess invocation pattern
  - Spawns: `powershell.exe` or `pwsh.exe` via `Process.Start(ProcessStartInfo)`
  - Script: `Deploy-Lab.ps1` located in lab sources directory
  - Communication: Arguments via command-line, temporary JSON files for VM configurations
  - VM config file: Temporary JSON written to `%TEMP%\lab-vms-{Guid}.json`, deleted after execution
  - Arguments passed: `-LabName`, `-LabPath`, `-SwitchName`, `-SwitchType`, `-DomainName`, `-VMsJsonFile`
  - Error handling: Captures stdout/stderr, reads process exit codes
  - Async execution: `RunPowerShellScriptAsync()` and `RunPowerShellAsync()` methods

- **Removal Operations:**
  - Generates PowerShell script dynamically via `StringBuilder`
  - Operations: `Stop-VM`, `Remove-VM`, `Remove-VMSwitch` (if needed)
  - Execution: Same subprocess pattern as deployment

**Hyper-V Management:**
- Local WMI queries only (no remote management detected)
- Namespace: `root\virtualization\v2`
- Operations: RequestStateChange method invocations for VM state transitions
- No remote/WinRM access to other hosts

## Import/Export

**Lab Configurations:**
- **Export**: Lab config serialized to JSON
  - Serializer: `System.Text.Json.JsonSerializer.Serialize(config.VMs, new JsonSerializerOptions { WriteIndented = true })`
  - Output file: Temporary file in `%TEMP%` for script argument passing

- **Import**: Lab config deserialized from JSON files
  - Deserializer: `System.Text.Json.JsonSerializer.Deserialize<AppSettings>(json)`
  - File dialog: `OpenFileDialog` for user selection

- **File format**: JSON (VMs array, network settings, domain name, memory, processors, disk size)

**Model Classes:**
- `LabConfig.cs` - Lab-level configuration (name, path, description, network, VMs, custom roles, domain)
- `VMDefinition.cs` - VM-level configuration (name, role, memory, processors, disk size, ISO, network adapter)
- `NetworkConfig.cs` - Network settings (switch name, type, IP prefix)
- `VirtualMachine.cs` - Runtime VM state (name, state, role, memory, processors, disk, IP, uptime, snapshot, creation date)
- `AppSettings.cs` - Application settings (paths, network defaults, behavior flags)

---

*Integration audit: 2026-02-21*
