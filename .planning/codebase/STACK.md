# Technology Stack

**Analysis Date:** 2026-02-16

## Languages

**Primary:**
- PowerShell 5.1+ - Core scripting language for all automation, orchestration, and VM management
- XAML - WPF UI definition for GUI components

**Secondary:**
- Bash - Linux VM configuration scripts (`Scripts/Configure-LIN1.sh`)
- JSON - Configuration, settings persistence, inventory, and run artifacts

## Runtime

**Environment:**
- Windows PowerShell 5.1+ (minimum required version per `SimpleLab.psd1`)
- .NET Framework (bundled with Windows PowerShell)
- Hyper-V hypervisor (Windows 10/11 Pro, Enterprise, or Education)

**Package Manager:**
- PowerShell Gallery (for module distribution)
- No lockfile present (PowerShell modules don't use lockfiles)

**Platform Requirements:**
- Windows 10/11 with Hyper-V enabled
- Administrator privileges required for most operations
- 16 GB+ RAM and fast SSD strongly recommended for multi-VM hosting

## Frameworks

**Core:**
- **Hyper-V** - Native Windows hypervisor for VM hosting, networking, and snapshot management
- **WPF (Windows Presentation Foundation)** - GUI framework via `PresentationFramework`, `PresentationCore`, `WindowsBase` assemblies
  - Implementation: `GUI/Start-OpenCodeLabGUI.ps1`, `OpenCodeLab-GUI.ps1`
  - XAML files: `GUI/MainWindow.xaml`, `GUI/Views/*.xaml`, `GUI/Components/VMCard.xaml`
  - Theme system: `GUI/Themes/Dark.xaml`, `GUI/Themes/Light.xaml`

**Testing:**
- **Pester 5.0+** - PowerShell testing framework
  - Config: Programmatic via `New-PesterConfiguration` in `Tests/Run.Tests.ps1`
  - 28 test files in `Tests/` directory
  - Auto-install: `Install-Module -Name Pester` if missing
  - Coverage: XML export to `Tests/coverage.xml`

**Build/Dev:**
- **PowerShell Language Parser** - Syntax validation via `[System.Management.Automation.Language.Parser]::ParseFile()` in `Scripts/Run-OpenCodeLab.ps1`
- **PSScriptAnalyzer 1.24.0** - Linting (bundled in `.tools/powershell-lsp/`)
- **OpenCode Plugin** - Development integration via `.opencode/package.json` with `@opencode-ai/plugin: 1.2.4`

## Key Dependencies

**Critical:**
- **Hyper-V PowerShell Module** - VM lifecycle management (`Get-VM`, `New-VM`, `Get-VMSwitch`, etc.)
  - Used throughout `Public/` and `Private/` helpers
  - Required for all VM operations
- **SimpleLab PowerShell Module** (this codebase) - Modular lab automation
  - Manifest: `SimpleLab.psd1` (v5.0.0)
  - Root module: `SimpleLab.psm1`
  - 107 helper functions across `Private/` and `Public/` directories

**Infrastructure:**
- **cloud-init** - Linux VM provisioning via `cidata` VHDX for LIN1 Ubuntu node
  - Generated: `Deploy.ps1` calls `New-CidataVhdx`
- **OpenSSH** - SSH key generation and Linux connectivity
  - Functions: `New-LabSSHKey`, `Get-LinuxSSHConnectionInfo` in `Public/Linux/`
- **System.Windows.Forms** - Dialog boxes in GUI helpers (`OpenCodeLab-GUI.ps1`)
- **System.Security** - Password hashing for Linux (SHA-512 via `Get-Sha512PasswordHash` in `Public/Linux/`)

**Optional:**
- **Ansible** - Optional automation tooling
  - Installation script: `Scripts/Install-Ansible.ps1`
  - Inventory format: JSON with top-level `hosts` array

## Configuration

**Environment:**
- Password/secrets via environment variables:
  - `OPENCODELAB_ADMIN_PASSWORD` - Admin password for lab operations
  - `LAB_ADMIN_PASSWORD` - LabBuilder password override
  - `OPENCODELAB_DISPATCH_MODE` - Dispatcher execution mode (off|canary|enforced)
- Configured in `Lab-Config.ps1` via `$GlobalLabConfig` hashtable
- Precedence: Explicit script parameters > environment variables > defaults

**Build:**
- Module manifest: `SimpleLab.psd1` (PowerShell metadata, version, exports)
- Lab configuration: `Lab-Config.ps1` (network, credentials, paths, VM topology)
- GUI settings: `.planning/gui-settings.json` (theme, window state, user preferences)
- Run artifacts: `.planning/runs/*.json` (execution history, state, outcomes)

**Data Formats:**
- **JSON** - Settings persistence, run artifacts, inventory, templates
- **XAML** - WPF UI definitions, themes, component layouts
- **XML** - Pester test coverage reports
- **TXT** - Run logs in `run-logs/` directories

## Platform Requirements

**Development:**
- Windows 10/11 Pro/Enterprise/Education
- PowerShell 5.1 or higher
- Hyper-V feature enabled
- Administrator privileges
- Visual Studio Code or PowerShell ISE (recommended)
- Git for version control

**Production:**
- Hyper-V host with sufficient resources:
  - 16 GB+ RAM (more for additional VMs)
  - Fast SSD storage (100 GB+ free recommended)
  - Multi-core CPU with hardware virtualization (Intel VT-x/AMD-V)
- Windows Server 2016+ or Windows 10/11 Pro+
- ISO images in `C:\LabSources\ISOs\`:
  - `server2019.iso` - Windows Server 2019 for DC1/SVR1
  - `win11.iso` - Windows 11 for WS1
  - `ubuntu-24.04-live-server-amd64.iso` - Ubuntu Server 24.04 for LIN1 (optional)

**Deployment:**
- Lab network: Hyper-V internal switch + NAT (default: `10.0.10.0/24`)
- Lab storage: `C:\AutomatedLab\` (VM files, checkpoints)
- Lab sources: `C:\LabSources\` (ISOs, scripts, logs, reports)
- Lab share: `C:\LabShare\` (SMB share for Linux/guest access)

## Entry Points

**CLI:**
- `OpenCodeLab-App.ps1` - Main orchestration app (menu, deploy, teardown, status, health)
  - Requires: Administrator privileges
  - Usage: `.\OpenCodeLab-App.ps1 -Action <action> [-Mode quick|full] [-NonInteractive]`
- `Bootstrap.ps1` - One-click lab setup (NuGet, Pester, dependencies, vSwitch, NAT, deploy)
  - Requires: Administrator privileges
  - First-run tool for initial environment configuration
- `Deploy.ps1` - Core deployment logic (VM creation, domain setup, snapshot management)
  - Requires: Administrator privileges
  - Called by `OpenCodeLab-App.ps1` or `Bootstrap.ps1`
- `Scripts/Run-OpenCodeLab.ps1` - Lightweight launcher with syntax validation
  - Usage: `.\Scripts\Run-OpenCodeLab.ps1 [-GUI] [-SkipBuild]`

**GUI:**
- `GUI/Start-OpenCodeLabGUI.ps1` - WPF GUI entry point (loads assemblies, XAML, settings)
  - Requires: PowerShell 5.1+ (not Administrator for viewing status)
  - Launched via: `.\Scripts\Run-OpenCodeLab.ps1 -GUI`
- `OpenCodeLab-GUI.ps1` - Legacy GUI bootstrap (delegates to `Start-OpenCodeLabGUI.ps1`)

**Testing:**
- `Tests/Run.Tests.ps1` - Pester test runner (auto-installs Pester 5.0+, runs all tests, generates coverage)
  - Usage: `.\Tests\Run.Tests.ps1 [-Verbosity Normal|Detailed]`

## Module Structure

**SimpleLab PowerShell Module:**
- `SimpleLab.psd1` - Module manifest (version 5.0.0, PowerShell 5.1+ required)
- `SimpleLab.psm1` - Root module file
- `Public/` - 50+ exported functions (VM management, network, domain, Linux helpers)
  - Subdirectories: `Linux/` (Ubuntu/SSH helpers)
- `Private/` - 50+ internal helpers (state probes, coordination, artifacts, tokens)
- `GUI/` - WPF GUI components and views
  - Subdirectories: `Public/`, `Private/`, `Views/`, `Themes/`, `Components/`
- `LabBuilder/` - Template-based lab construction helpers
- `Scripts/` - Utility scripts (health checks, status reports, Ansible setup, terminal launch)
- `Tests/` - 28 Pester test files covering coordinators, dispatchers, GUI, and private helpers

---

*Stack analysis: 2026-02-16*
