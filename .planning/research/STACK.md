# Stack Research

**Domain:** PowerShell/Hyper-V Windows Domain Lab Automation
**Researched:** 2026-02-09
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
- [PowerShell Direct - Microsoft Learn](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell-direct) — HIGH confidence, official docs (Oct 2025)

---
*Stack research for: PowerShell/Hyper-V Windows Domain Lab Automation*
*Researched: 2026-02-09*
