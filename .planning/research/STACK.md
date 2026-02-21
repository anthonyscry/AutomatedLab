# Stack Research

**Domain:** PowerShell/Hyper-V Windows Domain Lab Automation
**Researched:** 2026-02-09 (v1.0 baseline) | Updated 2026-02-20 (v1.6 additions)
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **Windows PowerShell** | 5.1 (built-in) | Core scripting engine | Ships with Windows 10/11, full Hyper-V module support, mature ecosystem. Windows PowerShell 7.x has limited Hyper-V cmdlet support. |
| **Hyper-V Module** | Built-in (Windows Server/Hyper-V feature) | VM provisioning and management | Native Windows module for complete Hyper-V control. Includes New-VM, Start-VM, Get-VM, Checkpoint-VM, Remove-VM. No third-party dependencies. |
| **Microsoft.PowerShell.PSResourceGet** | 1.1.1+ | Package management | Official replacement for PowerShellGet v2. Faster, more reliable, handles dependencies better. Generally available since Oct 2023. |
| **PowerShellGet (compatibility layer)** | 3.0+ | Backward compatibility | Compatibility layer between PSResourceGet and legacy module installations. Required for modules still using old manifests. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **Pester** | 5.7.1+ | Unit/integration testing | Test your lab deployment scripts, validate VM states, verify domain joins. Essential for reliability. |
| **PSFramework** | 1.13.414+ | Logging, configuration, validation | Provides structured logging, configuration management, and parameter validation. Reduces boilerplate code significantly. |
| **PSScriptAnalyzer** | Latest | Code linting | Static analysis to catch code quality issues before deployment. Use in pre-commit hooks. |

### Hyper-V-Specific Cmdlets (Built-in)

| Cmdlet Set | Purpose | Notes |
|------------|---------|-------|
| `New-VM`, `Remove-VM` | VM lifecycle | Gen2 VMs, VHDX format, static memory for simplicity |
| `Start-VM`, `Stop-VM` | VM power control | Use `Stop-VM -TurnOff` for forced shutdowns during cleanup |
| `Get-VMNetworkAdapter` | Network configuration | Verify IP assignment, troubleshoot connectivity |
| `Checkpoint-VM` | Snapshots | Fast rollback to known-good states |
| `New-VMSwitch`, `Get-VMSwitch` | Virtual networking | Internal switches for lab isolation + NAT |
| `New-NetIPAddress`, `New-NetNat` | Host networking | Configure gateway IPs and NAT for lab connectivity |
| `Invoke-Command` | Remote execution | WinRM-based; use `New-PSSession` for repeated operations |
| `PowerShell Direct` | VM communication without network | Use `Enter-PSSession -VMName` for offline troubleshooting |

## Installation

```powershell
# Prerequisite: Run as Administrator
# Requires Hyper-V role enabled

# 1. Enable Hyper-V if not already enabled
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# 2. Install package management
Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force -Scope AllUsers
Install-Module -Name PowerShellGet -Force -Scope AllUsers  # Compatibility layer

# 3. Install supporting modules
Install-Module -Name Pester -Force -Scope AllUsers -SkipPublisherCheck -MinimumVersion 5.7.1
Install-Module -Name PSFramework -Force -Scope AllUsers -MinimumVersion 1.13.414
Install-Module -Name PSScriptAnalyzer -Force -Scope AllUsers

# 4. Verify Hyper-V module availability
Get-Command -Module Hyper-V | Select-Object -First 10
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **Native Hyper-V module** | AutomatedLab | Use AutomatedLab for complex multi-product labs (Exchange, SQL, etc.). For simple Windows domain labs, native cmdlets are faster, simpler, and have fewer dependencies. |
| **PowerShell 5.1** | PowerShell 7.x | Use PowerShell 7 for cross-platform scripts. Stay on 5.1 for Hyper-V automation—many Hyper-V cmdlets lack PS7 support. |
| **PSResourceGet** | PowerShellGet v2 | PSResourceGet is the future. PowerShellGet v2 is deprecated, slower, and has known issues with dependency resolution. |
| **WinRM/Invoke-Command** | SSH remoting | Use SSH remoting for Linux VMs. For Windows, WinRM is built-in and requires no additional setup. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **AutomatedLab for simple domain labs** | Overkill. Adds complexity (ISO detection, disclaimers, role abstraction) you don't need for 2-3 VM labs. Slow builds due to generic abstraction layers. | Native Hyper-V cmdlets. Define your VMs directly with `New-VM`, configure with `Invoke-Command`. |
| **Default Switch** for labs | Subnet changes on host reboot, breaking static IPs and NAT configuration. Unpredictable behavior. | Dedicated Internal vSwitch + host NAT with `New-VMSwitch -SwitchType Internal` and `New-NetNat`. |
| **PowerShellGet v2** | Deprecated. Performance issues. Known bugs with package dependency resolution. | `Microsoft.PowerShell.PSResourceGet` (PSResourceGet). |
| **Checkpoints for production labs** | VHDX grows indefinitely. Not suitable for long-running labs. | For testing only. For production-style labs, use fresh VM builds from sysprep'd templates. |
| **Dynamic memory** | Adds complexity. Can cause performance issues during DC promotion and heavy operations. | Static memory (4GB per VM minimum for Server 2019/2022). |
| **Third-party ISO converters** | Unnecessary. Windows Server ISOs already contain everything needed. | Use `Convert-WindowsImage.ps1` (Microsoft-signed) or direct VHDX creation from ISO. |

## Stack Patterns by Variant

**If you need Windows-only domain labs:**
- Use Windows PowerShell 5.1 + Hyper-V module
- Because: Full cmdlet coverage, no compatibility issues, ships with OS

**If you need Linux + Windows labs:**
- Add SSH remoting for Linux, WinRM for Windows
- Because: Each platform has its native remoting protocol. Don't fight the tools.

**If you need Azure integration:**
- Consider AutomatedLab or Azure PowerShell modules
- Because: Native Hyper-V cmdlets won't reach Azure. The complexity payoff is justified.

**If you need offline environments:**
- Pre-download modules with `Save-Module` to a network share
- Because: `Install-Module` requires internet. PSResourceGet supports local repositories.

## Version Compatibility

| Package | Compatible With | Notes |
|-----------|-----------------|-------|
| **PowerShell 5.1** | Windows 10/11, Windows Server 2019/2022/2025 | Built into OS. No installation required. |
| **PSResourceGet 1.1.1** | PowerShell 5.1+, PowerShell 7.2+ | Requires .NET 4.7.1+ on PS 5.1. Ships with PS 7.3+. |
| **Pester 5.7.1** | PowerShell 5.1+, PowerShell 7.2+ | Breaking changes from Pester 4.x. Update existing tests. |
| **PSFramework 1.13.414** | PowerShell 5.1+, PowerShell 7+ | Actively maintained (v1.13.414 released Oct 2025). |
| **Hyper-V module** | Windows 10/11 Pro/Ent, Windows Server 2016+ | Client HyperV has limitations (max ~100 VMs). Server HyperV recommended for frequent lab resets. |

## Key Hyper-V Cmdlets by Task

```powershell
# VM Creation
New-VM -Name "DC1" -MemoryStartupBytes 4GB -NewVHDPath "C:\VMs\DC1.vhdx" -NewVHDSizeBytes 60GB -Generation 2 -SwitchName "LabSwitch"

# VM Configuration
Set-VMProcessor -VMName "DC1" -Count 4
Set-VMMemory -VMName "DC1" -DynamicMemoryEnabled $false -StartupBytes 4GB

# Network Configuration
New-VMSwitch -Name "LabSwitch" -SwitchType Internal
New-NetIPAddress -InterfaceAlias "vEthernet (LabSwitch)" -IPAddress "192.168.11.1" -PrefixLength 24
New-NetNat -Name "LabNat" -InternalIPInterfaceAddressPrefix "192.168.11.0/24"

# VM Integration Services
Enable-VMIntegrationService -VMName "DC1" -Name "Guest Service Interface"  # File copy

# Snapshot Management
Checkpoint-VM -Name "DC1" -SnapshotName "Baseline"
Restore-VMSnapshot -Name "DC1" -SnapshotName "Baseline"

# Cleanup
Remove-VM -Name "DC1" -Force
```

---

## v1.6 Stack Additions

*Added 2026-02-20. Covers: Lab TTL/auto-suspend, PowerSTIG DSC baselines, ADMX/GPO auto-import, dashboard enrichment.*

### New Core Technologies (v1.6)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **PowerSTIG** | 4.28.0 | Apply DISA STIG DSC baselines per VM role at deploy time | Official Microsoft module (microsoft/PowerStig), PS 5.1 minimum requirement verified on PSGallery. Quarterly release cadence — v4.28.0 released 2025-12-05. Composite DSC resources (`WindowsServer`) map directly to `OsRole` (MS/DC) and `OsVersion` (2019/2022). Eliminates hand-maintained STIG scripts. |
| **ScheduledTasks module** | Built-in (Windows 8.1+) | Register recurring TTL monitor task on the Hyper-V host | Ships with OS. `Register-ScheduledTask`, `New-ScheduledTaskTrigger`, `New-ScheduledTaskAction`, `New-ScheduledTaskSettingsSet` cover the full lifecycle. Tasks survive host reboots and are visible in Task Scheduler UI for operator inspection. No install needed. |
| **GroupPolicy module** | Built-in (DC role / RSAT) | Import GPO backups, link GPOs, copy ADMX to Central Store | Ships with Active Directory Domain Services role and RSAT. Available on DC VM after promotion. Invoked via `Invoke-LabCommand` against the DC — same pattern as all other post-provision steps. Key cmdlets: `Import-GPO`, `New-GPO`, `New-GPLink`. |
| **System.Windows.Threading.DispatcherTimer** | Built-in (.NET 4.x / WPF) | Drive periodic dashboard refresh for new metrics | Already in use at `Start-OpenCodeLabGUI.ps1:794` as `$script:VMPollTimer` with 5-second interval. Extend existing tick handler — no new infrastructure. |

### New Supporting Libraries (v1.6) — Guest VM Only

These install **on each guest VM** via `Invoke-LabCommand`, not on the Hyper-V host. They are exact-version dependencies of PowerSTIG 4.28.0.

| Library | Version | Purpose | Notes |
|---------|---------|---------|-------|
| **PSDscResources** | 2.12.0 | Core DSC composite resources | Required for all PowerSTIG targets |
| **AccessControlDsc** | 1.4.3 | File/folder ACL enforcement | Windows Server STIG targets |
| **AuditPolicyDsc** | 1.4.0 | Audit policy configuration | Windows Server STIG targets |
| **AuditSystemDsc** | 1.1.0 | System audit settings | Windows Server STIG targets |
| **CertificateDsc** | 5.0.0 | Certificate store management | Windows Server STIG targets |
| **ComputerManagementDsc** | 8.4.0 | Computer configuration settings | Windows Server STIG targets |
| **FileContentDsc** | 1.3.0.151 | File content configuration | Windows Server STIG targets |
| **GPRegistryPolicyDsc** | 1.3.1 | Registry policy settings | Windows Server STIG targets |
| **SecurityPolicyDsc** | 2.10.0 | Security policy enforcement | Windows Server STIG targets |
| **WindowsDefenderDsc** | 2.2.0 | Windows Defender configuration | Windows Server STIG targets |

> **Selective installation note:** PowerSTIG 4.28.0 lists 15 total dependencies; the 5 not listed above (`SqlServerDsc`, `Vmware.vSphereDsc`, `xWebAdministration`, `xDnsServer`, `nx`) apply only to SQL Server, VMware, IIS, DNS Server, and Linux STIG types respectively. For Windows Server OS STIGs (the v1.6 target), install only the 10 modules listed. Validate with `(Find-Module PowerSTIG -RequiredVersion 4.28.0).Dependencies` before finalising the install script.

### v1.6 Installation (Guest VMs Only)

```powershell
# Executed via Invoke-LabCommand inside each Windows Server role PostInstall hook
# Same pattern as existing DSCPullServer.ps1 Steps A-D

# Trust PSGallery
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

# Install PowerSTIG dependencies (exact versions — PowerSTIG 4.28.0 requirement)
$stigDeps = @(
    @{ Name = 'AccessControlDsc';      RequiredVersion = '1.4.3'     }
    @{ Name = 'AuditPolicyDsc';        RequiredVersion = '1.4.0'     }
    @{ Name = 'AuditSystemDsc';        RequiredVersion = '1.1.0'     }
    @{ Name = 'CertificateDsc';        RequiredVersion = '5.0.0'     }
    @{ Name = 'ComputerManagementDsc'; RequiredVersion = '8.4.0'     }
    @{ Name = 'FileContentDsc';        RequiredVersion = '1.3.0.151' }
    @{ Name = 'GPRegistryPolicyDsc';   RequiredVersion = '1.3.1'     }
    @{ Name = 'PSDscResources';        RequiredVersion = '2.12.0'    }
    @{ Name = 'SecurityPolicyDsc';     RequiredVersion = '2.10.0'    }
    @{ Name = 'WindowsDefenderDsc';    RequiredVersion = '2.2.0'     }
)
foreach ($dep in $stigDeps) {
    if (-not (Get-Module -ListAvailable -Name $dep.Name |
              Where-Object { $_.Version -eq $dep.RequiredVersion })) {
        Install-Module @dep -Force -Scope AllUsers
    }
}

# Install PowerSTIG
if (-not (Get-Module -ListAvailable -Name PowerSTIG |
          Where-Object { $_.Version -eq '4.28.0' })) {
    Install-Module -Name PowerSTIG -RequiredVersion 4.28.0 -Force -Scope AllUsers
}
```

### v1.6 Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| PowerSTIG 4.28.0 | Manual DSC scripts per STIG | Never for v1.6. PowerSTIG is Microsoft's official STIG automation module with quarterly-updated composite resources. Manual scripts require constant maintenance against DISA XCCDF releases. |
| ScheduledTasks module (built-in) | `Start-Job` / persistent runspace | Use `Start-Job` for one-shot async tasks, not recurring monitoring. Scheduled tasks survive host reboots, run under a defined principal, and appear in Task Scheduler UI. |
| GroupPolicy module via `Invoke-LabCommand` on DC | RSAT on Hyper-V host | GroupPolicy module is available on the DC after promotion. `Invoke-LabCommand` is the established project pattern — no additional RSAT install on the host. |
| `Copy-Item` over PS remoting for ADMX files | `robocopy` | `Copy-Item` is sufficient for ADMX file sets (hundreds of files). `robocopy` adds no meaningful benefit and requires `Start-Process` or `cmd.exe` invocation. |
| Extend existing `DispatcherTimer` tick handler | Separate runspace + synchronized hashtable | The 5-second `$script:VMPollTimer` already polls all VM state. Add snapshot age, disk, and compliance fields to `Get-LabStatus` output and `Update-VMCard`. A second runspace adds concurrency complexity with no benefit at this refresh rate. |

### v1.6 What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| DSC v3 / PSDesiredStateConfiguration 3.x | Requires PowerShell 7.2+. Project is locked to PS 5.1. | DSC v1.1 (built-in to PS 5.1) + PowerSTIG 4.28.0 which explicitly declares `PowerShellVersion = '5.1'` in its manifest. |
| DSC Pull mode for baseline application | Pull mode requires the DSCPullServer VM plus LCM registration per client. For one-time baseline application at deploy time, push mode is simpler, faster, and has no infrastructure dependency. | Push mode: compile MOF on host via `Invoke-Command`, apply with `Start-DscConfiguration -Path $mofPath -ComputerName $vmName -Wait -Force`. |
| `nx` DSC module (PowerSTIG Linux dependency) | Linux STIG targets only. The project does not use DSC for Linux VMs — Linux is handled via cloud-init and SSH. Installing on Windows VMs wastes time. | Skip — it is not in the 10-module Windows dependency set. |
| `Invoke-GPUpdate` to verify ADMX import | `Invoke-GPUpdate` schedules a refresh but does not wait for completion. Unreliable for post-import verification in automated scripts. | Use `Get-GPO -Name $gpoName` to verify import success. GP application to client VMs happens automatically on next refresh cycle. |

### v1.6 Integration Points

**Lab TTL / auto-suspend — Hyper-V host:**
- `Register-ScheduledTask` on the host with `RepetitionInterval` trigger (e.g., 15 minutes)
- Monitor script reads TTL config from `Lab-Config.ps1` (`$LabConfig.TTL.MaxIdleMinutes`)
- Calls `Stop-VM` or `Suspend-VM` (configurable) on VMs that exceed TTL
- Task registered under `\AutomatedLab\` folder in Task Scheduler

**PowerSTIG baselines — guest VM PostInstall:**
- Invocation point: inside `PostInstall` ScriptBlock of each Windows Server role (same as `DSCPullServer.ps1`)
- `OsRole` mapping: DC role → `'DC'`; all other server roles → `'MS'`
- `OsVersion` mapping: derived from `$Config.ServerOS` (e.g. `'2019'`, `'2022'`)
- Compile `WindowsServer` composite resource MOF, apply with `Start-DscConfiguration -Wait -Force`
- Store compliance result JSON to `.planning/compliance/<vmName>-latest.json`

**ADMX / GPO import — DC PostInstall:**
- After `Install-ADDSDomain` completes, run ADMX copy and GPO import as additional PostInstall steps
- Step 1: `Copy-Item` ADMX/ADML from host source to `\\$dcVMName\SYSVOL\$domain\Policies\PolicyDefinitions\`
- Step 2: `Invoke-LabCommand` on DC: `Import-Module GroupPolicy; Import-GPO -BackupId $guid -Path $backupPath -TargetName $gpoName`
- Step 3: `New-GPLink -Name $gpoName -Target "DC=$domain,DC=..."` to link GPO to domain root

**Dashboard enrichment — GUI tick handler:**
- Extend `Get-LabStatus` to return `SnapshotAgeHours`, `DiskFreeGB`, `UptimeHours`, `ComplianceStatus`
- `ComplianceStatus` reads from `.planning/compliance/<vmName>-latest.json` — file read only, no live DSC query
- Extend `Update-VMCard` XAML data binding to surface new fields
- No new timer — reuse `$script:VMPollTimer` at existing 5-second interval

### v1.6 Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| PowerSTIG 4.28.0 | PowerShell 5.1+ | PSGallery manifest `PowerShellVersion = '5.1'`. Released 2025-12-05. |
| PSDscResources 2.12.0 | PowerShell 5.1 / DSC v1.1 | Exact version required by PowerSTIG 4.28.0. |
| SecurityPolicyDsc 2.10.0 | PowerShell 5.1 / DSC v1.1 | Exact version required by PowerSTIG 4.28.0. |
| ScheduledTasks module | Windows 8.1 / Server 2012+ (built-in) | No version concern. Present on all supported host OS. |
| GroupPolicy module | Windows Server with AD DS or RSAT | Present on DC VM post-promotion. Not available on Hyper-V host without RSAT. |
| System.Windows.Threading.DispatcherTimer | .NET 4.x (already loaded by WPF host) | In use at `Start-OpenCodeLabGUI.ps1:794`. No change to initialization. |

---

## Sources

- [Microsoft Learn - PowerShell Overview](https://docs.microsoft.com/en-us/powershell/scripting/overview?view=powershell-7.5) — HIGH confidence, official docs
- [Microsoft Learn - Hyper-V PowerShell](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell) — HIGH confidence, official docs
- [PSResourceGet - Microsoft Dev Blog](https://devblogs.microsoft.com/powershell/psresourceget-is-generally-available/) — HIGH confidence, official announcement (Oct 2023)
- [PSResourceGet GitHub](https://github.com/PowerShell/PSResourceGet) — HIGH confidence, official repository
- [Pester GitHub](https://github.com/pester/Pester) — HIGH confidence, official repository, latest version 5.7.1 (Jan 2025)
- [PSFramework Blog - v1.13.414 Release](https://psframework.org/blog/release-psframework-v1.13.414/) — HIGH confidence, official release notes (Oct 2025)
- [AutomatedLab GitHub](https://github.com/AutomatedLab/AutomatedLab) — HIGH confidence, source code review for complexity assessment
- [AutomatedLab Official Site](https://automatedlab.org/) — MEDIUM confidence, feature documentation
- [Windows Server 2025 Hyper-V Implementation](https://lenovopress.lenovo.com/lp2198-implementing-hyper-v-on-microsoft-windows-server-2025) — MEDIUM confidence, technical whitepaper (Apr 2025)
- [PowerShell Direct - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/dsc/overview?view=dsc-1.1) — HIGH confidence, official docs (Oct 2025)
- [PowerShell Gallery — PowerSTIG 4.28.0](https://www.powershellgallery.com/packages/PowerSTIG/4.28.0) — HIGH confidence, dependency list and PS minimum version verified directly
- [Microsoft Learn — GroupPolicy Module (WS2025)](https://learn.microsoft.com/en-us/powershell/module/grouppolicy/?view=windowsserver2025-ps) — HIGH confidence, official cmdlet inventory
- [Microsoft Learn — Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps) — HIGH confidence, official API docs
- [microsoft/PowerStig Wiki — WindowsServer](https://github.com/microsoft/PowerStig/wiki/WindowsServer) — HIGH confidence, OsRole/OsVersion parameters
- Project codebase `GUI/Start-OpenCodeLabGUI.ps1:794` — HIGH confidence, existing DispatcherTimer pattern (direct read)
- Project codebase `LabBuilder/Roles/DSCPullServer.ps1` — HIGH confidence, existing push-mode DSC pattern (direct read)

---

*Stack research for: PowerShell/Hyper-V Windows Domain Lab Automation*
*Researched: 2026-02-09 | v1.6 additions: 2026-02-20*
