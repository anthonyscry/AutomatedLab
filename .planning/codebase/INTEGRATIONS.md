# External Integrations

**Analysis Date:** 2026-02-16

## APIs & External Services

**Software Distribution:**
- GitHub Releases - Git for Windows download
  - URL: `https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe`
  - Configuration: `Lab-Config.ps1` `$GlobalLabConfig.SoftwarePackages.Git`
  - SHA-256 validation: `0229E3ACB535D0DC5F0D4A7E33CD36E3E3BA5B67A44B507B4D5E6A63B0B8BBDE`

**No external cloud services** - Lab runs entirely on local Hyper-V infrastructure

## Data Storage

**Databases:**
- SQL Server (optional role) - Installable via LabBuilder templates
  - Instance: `MSSQLSERVER` (default instance name per `Lab-Config.ps1`)
  - SA password: `$GlobalLabConfig.Credentials.SqlSaPassword` (default: `SimpleLabSqlSa123!`)
  - Configuration: `Lab-Config.ps1` `$GlobalLabConfig.Builder.IPPlan.SQL` → `10.0.10.60`
  - Supported roles: `SQL1` (Windows Server), `LINDB1` (Ubuntu database node)

**File Storage:**
- Local filesystem only
  - Lab VMs: `C:\AutomatedLab\` (default per `Lab-Config.ps1`)
  - Lab sources: `C:\LabSources\` (ISOs, scripts, logs, reports)
  - ISO storage: `C:\LabSources\ISOs\`
  - SMB share: `C:\LabShare\` (exposed to VMs/Linux guests)
- Guest storage: Dynamic VHDX files attached to Hyper-V VMs

**Caching:**
- None - No distributed cache services

**Artifacts:**
- JSON files in `.planning/runs/*.json` (run history, execution outcomes)
- Text logs in `run-logs/` subdirectories (deployment logs, action outputs)
- Templates in `.planning/templates/*.json` (VM topology definitions)
- Configuration in `.planning/config.json` (active template selection)
- GUI settings in `.planning/gui-settings.json` (theme, window state)
- Coverage reports in `Tests/coverage.xml` (Pester test coverage)

## Authentication & Identity

**Auth Provider:**
- Active Directory Domain Services (AD DS) - Local domain controller
  - Domain: `simplelab.local` (default per `Lab-Config.ps1`)
  - DC VM: `DC1` at `10.0.10.10`
  - Admin user: `admin` (configurable via `$GlobalLabConfig.Credentials.InstallUser`)
  - Admin password: Environment variable `OPENCODELAB_ADMIN_PASSWORD` or fallback from `Lab-Config.ps1`
  - Implementation: Windows Server 2019 AD DS role on DC1

**SSH Keys:**
- OpenSSH key generation for Linux VMs
  - Function: `New-LabSSHKey` in `Public/`
  - Usage: LIN1 Ubuntu node SSH access
  - Connection info: `Get-LinuxSSHConnectionInfo` in `Public/Linux/`

**Password Management:**
- Environment variables (preferred):
  - `OPENCODELAB_ADMIN_PASSWORD` - Admin password for lab operations
  - `LAB_ADMIN_PASSWORD` - LabBuilder password override
- Fallback to `Lab-Config.ps1` hardcoded defaults (not recommended for production)
- Linux password hashing: SHA-512 via `Get-Sha512PasswordHash` in `Public/Linux/Get-Sha512PasswordHash.ps1`

## Monitoring & Observability

**Error Tracking:**
- None - No external error tracking service

**Logs:**
- Local text files in `run-logs/` directories
- PowerShell `Write-LabStatus` function for standardized output
- Run artifacts (JSON) in `.planning/runs/` with execution metadata
- Windows Event Logs on guest VMs (checked via `Deploy.ps1` AD recovery validation)

**Health Checks:**
- `Scripts/Test-OpenCodeLabHealth.ps1` - Comprehensive lab health validation
- `Scripts/Test-OpenCodeLabPreflight.ps1` - Pre-deployment checks
- `Scripts/Lab-Status.ps1` - VM/network/domain status reporting
- `OpenCodeLab-App.ps1` - Built-in health action (`-Action health`)

## CI/CD & Deployment

**Hosting:**
- Local Hyper-V on Windows 10/11 or Windows Server
- No cloud hosting

**CI Pipeline:**
- None - Manual testing via Pester
- Test runner: `Tests/Run.Tests.ps1` (local execution only)
- Syntax validation: `Scripts/Run-OpenCodeLab.ps1` via PowerShell Language Parser

**Deployment:**
- Local orchestration via `OpenCodeLab-App.ps1`
- Multi-host support via inventory JSON files (optional)
- Ansible integration available via `Scripts/Install-Ansible.ps1`

## Environment Configuration

**Required env vars:**
- `OPENCODELAB_ADMIN_PASSWORD` - Admin password for lab operations (strongly recommended)
- `LAB_ADMIN_PASSWORD` - LabBuilder password override (optional)
- `OPENCODELAB_DISPATCH_MODE` - Dispatcher execution mode: `off|canary|enforced` (optional)

**Optional env vars:**
- Git configuration: `$GlobalLabConfig.Credentials.GitName`, `GitEmail` for automated git operations

**Secrets location:**
- Environment variables (preferred method)
- `Lab-Config.ps1` hardcoded defaults (fallback, not recommended for shared environments)
- No secret management service integration

**Configuration files:**
- `Lab-Config.ps1` - Global lab configuration (network, credentials, paths, VM topology)
- `.planning/config.json` - Active template selection
- `.planning/gui-settings.json` - GUI user preferences
- `.planning/templates/*.json` - VM deployment templates

## Webhooks & Callbacks

**Incoming:**
- None - No webhook listeners

**Outgoing:**
- None - No webhook triggers

## Network Services

**Hyper-V Networking:**
- Internal vSwitch: `AutomatedLab` (default per `Lab-Config.ps1`)
  - Address space: `10.0.10.0/24`
  - Gateway IP: `10.0.10.1`
  - NAT name: `AutomatedLabNAT`
- DNS: `10.0.10.10` (DC1 domain controller)

**SMB File Sharing:**
- Share name: `LabShare` (per `$GlobalLabConfig.Paths.ShareName`)
- Host path: `C:\LabShare\` (per `$GlobalLabConfig.Paths.SharePath`)
- Linux mount point: `/mnt/labshare` (per `$GlobalLabConfig.Paths.LinuxLabShareMount`)
- Git repo staging: `C:\LabShare\GitRepo\` (per `$GlobalLabConfig.Paths.GitRepoPath`)
- Implementation: SMB/CIFS for cross-platform file access

**DHCP:**
- Windows DHCP Server (optional role on DC1)
  - Scope ID: `10.0.10.0`
  - Range: `10.0.10.100` - `10.0.10.200`
  - Subnet mask: `255.255.255.0`
  - Configuration: `Lab-Config.ps1` `$GlobalLabConfig.DHCP`
  - Usage: Dynamic addressing for Linux VMs and additional nodes

**WinRM:**
- Windows Remote Management for VM orchestration
  - Checked via `Scripts/Lab-Status.ps1` (HTTPS listener detection)
  - Used by `Invoke-Command` for guest VM operations

## Optional Role Integrations

**Available via LabBuilder templates:**

- **IIS (Internet Information Services)** - Web server role
  - Template: `LabBuilder/Roles/IIS.ps1`
  - IP: `10.0.10.50` (per `$GlobalLabConfig.Builder.IPPlan.IIS`)

- **WSUS (Windows Server Update Services)** - Update management
  - Template: `LabBuilder/Roles/WSUS.ps1`
  - IP: `10.0.10.70` (per `$GlobalLabConfig.Builder.IPPlan.WSUS`)

- **DSC (Desired State Configuration)** - Pull server
  - Template: `LabBuilder/Roles/DSCPullServer.ps1`
  - IP: `10.0.10.40` (per `$GlobalLabConfig.Builder.IPPlan.DSC`)

- **File Server** - SMB file services
  - IP: `10.0.10.80` (per `$GlobalLabConfig.Builder.IPPlan.FileServer`)

- **Print Server** - Print services
  - IP: `10.0.10.85` (per `$GlobalLabConfig.Builder.IPPlan.PrintServer`)

**All integrations are local lab services** - No external SaaS dependencies

## Cloud-Init Integration

**Linux Provisioning:**
- cloud-init for Ubuntu VMs (LIN1, LINWEB1, LINDB1, LINDOCK1, LINK8S1)
  - Method: `cidata` VHDX attached to VM (ISO 9660 filesystem)
  - Generator: `New-CidataVhdx` function (called in `Deploy.ps1`)
  - Autoinstall: Ubuntu Server 24.04/22.04 `autoinstall` mode
  - Configuration: User-data, meta-data, network-config in cidata image
- Supported distros: Ubuntu 24.04 LTS, Ubuntu 22.04 LTS, Rocky Linux 9 (per `Lab-Config.ps1`)

---

*Integration audit: 2026-02-16*
