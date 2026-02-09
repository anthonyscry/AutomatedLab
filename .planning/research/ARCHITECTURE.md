# Architecture Research

**Domain:** PowerShell Hyper-V Lab Automation
**Researched:** 2026-02-09
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CLI / Orchestrator Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │   Main App   │  │   Config     │  │   Validator  │  │   Reporter   │   │
│  │   Entry Pt   │  │   Manager    │  │   Preflight  │  │   Logging    │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
└─────────┼──────────────────┼──────────────────┼──────────────────┼───────────┘
          │                  │                  │                  │
┌─────────┴──────────────────┴──────────────────┴──────────────────┴───────────┐
│                           Core Automation Layer                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │   Network    │  │     VM       │  │   Domain     │  │   Template   │   │
│  │   Manager    │  │   Provision  │  │   Config     │  │   Manager    │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
└─────────┼──────────────────┼──────────────────┼──────────────────┼───────────┘
          │                  │                  │                  │
┌─────────┴──────────────────┴──────────────────┴──────────────────┴───────────┐
│                        Infrastructure Layer                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │   Hyper-V    │  │   PowerShell │  │     ISO      │  │   Storage    │   │
│  │   Cmdlets    │  │   Remoting   │  │   Sources    │  │   Volumes    │   │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **Main App/Orchestrator** | Single entry point; action routing; user interaction menu | PowerShell script with param() blocks for action selection |
| **Config Manager** | Load/validate lab configuration from file or environment | Dot-sourced .psd1 or .ps1 config files; environment variable fallbacks |
| **Validator (Preflight)** | Verify prerequisites before VM creation (ISOs, Hyper-V, RAM, disk) | Separate Test-* script with structured checks and retry logic |
| **Network Manager** | Create vSwitches, NAT networks, IP addressing | Hyper-V module (Get-VMSwitch, New-VMSwitch); NetNat module |
| **VM Provisioner** | Create VMs, attach ISOs/VHDx, configure hardware | Hyper-V module (New-VM, Set-VM, Add-VMNetworkAdapter) |
| **Domain Configurer** | Promote DCs, join domains, configure DNS/AD/DHCP | Invoke-LabCommand; DSC configurations; AD PowerShell cmdlets |
| **Template Manager** | Manage VM snapshots/checkpoints for fast rebuilds | Checkpoint-VM, Restore-VMSnapshot, Get-VMSnapshot |
| **Health Checker** | Validate lab state post-deployment (services, shares, connectivity) | Structured checks with retry loops; Invoke-LabCommand |
| **Reporter/Logger** | JSON/text run artifacts; console feedback; error tracking | Custom logging functions; PSCustomObject for structured output |

## Recommended Project Structure

```
SimpleLab/
├── SimpleLab-App.ps1         # Main orchestrator/entry point
├── SimpleLab-Config.ps1      # Central configuration (all user-editable values)
├── SimpleLab-Common.ps1      # Shared helpers, functions, utilities
├── SimpleLab-Bootstrap.ps1   # One-time setup (module installs, folder creation)
├── SimpleLab-Deploy.ps1      # Lab VM provisioning and configuration
├── SimpleLab-Status.ps1      # Lab status dashboard (VM states, resources)
├── SimpleLab-Preflight.ps1   # Pre-deployment validation (ISOs, Hyper-V, capacity)
├── SimpleLab-Health.ps1      # Post-deployment health gate with rollback
├── SimpleLab-Teardown.ps1    # Clean removal of VMs and lab artifacts
├── SimpleLab-Rollback.ps1    # Restore to LabReady checkpoint
├── SimpleLab-Templates.ps1   # Template/snapshot management
├── Tests/                    # Health/validations
│   ├── Test-SimpleLabHealth.ps1
│   └── Test-SimpleLabPreflight.ps1
├── Assets/                   # Icons, images (if building GUI)
└── README.md
```

### Structure Rationale

- **SimpleLab-App.ps1:** Orchestrator pattern — single entry point routes to sub-scripts, simplifies user experience
- **SimpleLab-Config.ps1:** Configuration as code — all user-editable values in one place, environment variable overrides supported
- **SimpleLab-Common.ps1:** Shared utilities — functions imported across all scripts to reduce duplication
- **Bootstrap → Deploy → Health:** Pipeline pattern — each stage validates before proceeding, with rollback capability
- **Separate Test scripts:** Testability — health and preflight checks can be run independently and verified
- **One file per concern:** Single Responsibility Principle — each script does one thing well, making maintenance easier

## Architectural Patterns

### Pattern 1: Orchestrator-Worker Model

**What:** A main entry point (orchestrator) delegates tasks to specialized worker scripts, each handling a specific aspect of lab automation.

**When to use:** When building a CLI tool with multiple distinct operations (setup, teardown, status, rollback).

**Trade-offs:**
- **Pros:** Clear separation of concerns; easy to test individual components; can run workers standalone
- **Cons:** More files to maintain; requires careful parameter passing between orchestrator and workers

**Example:**
```powershell
# SimpleLab-App.ps1 (Orchestrator)
param(
    [ValidateSet('setup', 'status', 'teardown', 'rollback', 'menu')]
    [string]$Action = 'menu'
)

switch ($Action) {
    'setup'    { & .\SimpleLab-Deploy.ps1 @PSBoundParameters }
    'status'   { & .\SimpleLab-Status.ps1 }
    'teardown' { & .\SimpleLab-Teardown.ps1 @PSBoundParameters }
    'rollback' { & .\SimpleLab-Rollback.ps1 }
    'menu'     { Show-InteractiveMenu }
}
```

### Pattern 2: Configuration Layering

**What:** Load configuration from multiple sources with explicit precedence (environment variables > config file > defaults).

**When to use:** When supporting both interactive and non-interactive modes.

**Trade-offs:**
- **Pros:** Flexible for automation; reasonable defaults for humans; explicit override behavior
- **Cons:** More complex config loading logic; can be confusing if precedence isn't documented

**Example:**
```powershell
# SimpleLab-Config.ps1
$LabName = 'SimpleLab'
$DomainName = 'simple.lab'
$AdminPassword = if ($env:SIMPLELAB_ADMIN_PASSWORD) {
    $env:SIMPLELAB_ADMIN_PASSWORD
} else {
    'P@ssw0rd!'
}
```

### Pattern 3: Pipeline with Health Gates

**What:** Each major stage validates before proceeding; failures trigger automatic rollback to known-good state.

**When to use:** For long-running operations where failures are costly (lab deployment takes 30+ minutes).

**Trade-offs:**
- **Pros:** Fast failure detection; prevents leaving lab in broken state; self-healing
- **Cons:** Requires checkpoint/snapshot infrastructure; rollback adds complexity

**Example:**
```powershell
# SimpleLab-Deploy.ps1
try {
    # Stage 1: VM Provisioning
    New-LabVMs
    if (-not (Test-LabVMsReady)) { throw "VM provisioning failed" }

    # Stage 2: Domain Configuration
    Install-LabDomain
    if (-not (Test-LabDomainReady)) { throw "Domain setup failed" }

    # Stage 3: Post-Configuration
    Install-LabRoles
    if (-not (Test-LabHealth)) { throw "Health check failed" }

    # Create LabReady checkpoint on success
    Checkpoint-LabVM -SnapshotName 'LabReady'
} catch {
    Write-Error $_
    Restore-LabVMSnapshot -SnapshotName 'LabReady' -ErrorAction SilentlyContinue
    throw
}
```

### Pattern 4: Structured Health Checks with Retry

**What:** Health validations that retry with exponential backoff, return structured results, and surface specific failures.

**When to use:** For validating services that take time to start (AD, DNS, DHCP).

**Trade-offs:**
- **Pros:** Resilient to timing issues; clear failure messaging; testable
- **Cons:** Adds deployment time; requires careful timeout tuning

**Example:**
```powershell
function Invoke-LabStructuredCheck {
    param(
        [string]$ComputerName,
        [scriptblock]$ScriptBlock,
        [string]$RequiredProperty,
        [int]$Attempts = 3,
        [int]$DelaySeconds = 10
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $result = Invoke-LabCommand -ComputerName $ComputerName -ScriptBlock $ScriptBlock -PassThru
            if ($result.$RequiredProperty) { return $result }
        } catch { }
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds $DelaySeconds }
    }
    return $null
}
```

## Data Flow

### Request Flow

```
User Input
    ↓
SimpleLab-App.ps1 (Orchestrator)
    ↓
Load Config (SimpleLab-Config.ps1)
    ↓
Preflight Validation (SimpleLab-Preflight.ps1)
    ↓
    ├─ PASS → Continue
    └─ FAIL → Exit with error
    ↓
VM Provisioning (SimpleLab-Deploy.ps1)
    ↓
    ├─ Success → Health Check (SimpleLab-Health.ps1)
    └─ Failure → Rollback
    ↓
    ├─ Health PASS → Create LabReady Checkpoint
    └─ Health FAIL → Rollback to LabReady
    ↓
Return Status + Artifacts (JSON/Text logs)
```

### State Management

```
Lab State (Hyper-V + Config)
    ↓ (read)
Health Checks → Validate current state
    ↓ (write if valid)
Checkpoints → Snapshot known-good states
    ↓ (read on failure)
Rollback → Restore last valid state
```

### Key Data Flows

1. **Configuration Flow:** Config file → Environment variables → Defaults (precedence order)
2. **Deploy Flow:** Preflight → VM Creation → Domain Setup → Role Installation → Health Gate → Checkpoint
3. **Teardown Flow:** Stop VMs → Remove VMs → Optional: Remove Network → Preserve Checkpoints
4. **Health Flow:** Structured checks with retry → Aggregate results → Pass/Fail determination
5. **Logging Flow:** Run events → In-memory list → JSON artifact + Text summary at completion

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1-5 VMs (typical lab) | Single orchestrator, sequential VM provisioning is fine |
| 5-20 VMs (complex lab) | Parallel VM provisioning with PowerShell workflows; separate network segments |
| 20+ VMs (enterprise lab) | Consider AutomatedLab framework; dedicated infrastructure; resource quotas |

### Scaling Priorities

1. **First bottleneck:** RAM/Disk on host — preflight checks must validate capacity before starting
2. **Second bottleneck:** Sequential VM startup — parallelize with Start-Job or PowerShell Workflow for 5+ VMs

## Anti-Patterns

### Anti-Pattern 1: Monolithic Script

**What people do:** Put all functionality (validation, provisioning, configuration, health checks) in a single 2000+ line script.

**Why it's wrong:** Impossible to test; hard to debug; difficult to reuse components; merge conflicts in teams.

**Do this instead:** Split into focused scripts with clear responsibilities; use orchestrator pattern to coordinate.

### Anti-Pattern 2: No Health Gates

**What people do:** Deploy VMs without validating they actually work, leaving lab in broken state.

**Why it's wrong:** Users discover failures hours later; unclear what broke; manual cleanup required.

**Do this instead:** Implement structured health checks with automatic rollback to last known-good checkpoint.

### Anti-Pattern 3: Hardcoded Configuration

**What people do:** Hardcode IPs, VM names, and paths throughout scripts.

**Why it's wrong:** Cannot adapt to different environments; impossible to reuse; changes require editing multiple files.

**Do this instead:** Centralize all configuration in a single file with environment variable overrides.

### Anti-Pattern 4: Synchronous Long Operations Without Feedback

**What people do:** Run 30-minute operations with Write-Progress but no status updates or ability to recover.

**Why it's wrong:** Users think process hung; no way to resume after interruption; frustrating UX.

**Do this instead:** Implement step-by-step progress with clear stage names; write run artifacts for audit trail; support resume from checkpoints.

### Anti-Pattern 5: No Checkpoint Strategy

**What people do:** Create VMs but never snapshot, so every rebuild starts from scratch.

**Why it's wrong:** Rebuilds take hours instead of seconds; discourages experimentation; risky for testing.

**Do this instead:** Create "LabReady" checkpoint after successful deployment; restore on failure; provide rollback command.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| **Hyper-V** | PowerShell module (Hyper-V\*) | Requires admin; host must have Hyper-V role enabled |
| **AutomatedLab** | Import-Module + cmdlets | Optional; only needed for complex labs |
| **PowerShell Remoting** | Invoke-Command, Invoke-LabCommand | Requires WinRM; CredSSP for double-hop |
| **ISO Files** | File system checks | Pre-flight must verify ISO existence |
| **Network** | NetNat, Hyper-V vSwitch | Requires admin; consider IP conflicts |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **Orchestrator → Workers** | Direct script invocation with splatted parameters | Pass through relevant flags (Force, NonInteractive) |
| **All Scripts → Config** | Dot-sourcing config file at script start | Support environment variable overrides |
| **Deploy → Health** | Direct invocation; health script returns structured results | Use try/catch for rollback on failure |
| **All Scripts → Logging** | Shared logging functions from Common.ps1 | Write structured events for JSON artifact |

## Build Order Implications

Based on component dependencies and data flow, recommended build order:

1. **Phase 1: Foundation**
   - Config management (SimpleLab-Config.ps1)
   - Common utilities (SimpleLab-Common.ps1)
   - Basic logging/reporting

2. **Phase 2: Validation**
   - Preflight checks (SimpleLab-Preflight.ps1)
   - Health checks (Test-SimpleLabHealth.ps1)
   - Status reporting (SimpleLab-Status.ps1)

3. **Phase 3: Core Provisioning**
   - Network setup
   - VM provisioning
   - Domain configuration

4. **Phase 4: Lifecycle Management**
   - Checkpoint/snapshot management
   - Teardown
   - Rollback

5. **Phase 5: Orchestration**
   - Main orchestrator (SimpleLab-App.ps1)
   - Menu interface
   - Run artifact generation

**Rationale:** Validation before provisioning prevents failed builds. Lifecycle management before orchestration ensures rollback exists before complex operations. Core provisioning depends on config and utilities.

## Sources

- [AutomatedLab GitHub Repository](https://github.com/AutomatedLab/AutomatedLab) - Module structure overview (HIGH)
- [AutomatedLab Documentation](https://automatedlab.org/) - Architecture patterns and best practices (HIGH)
- [LabBuilder GitHub Repository](https://github.com/PlagueHO/LabBuilder) - Alternative lab automation architecture (MEDIUM)
- [Configuring a Hyper-V Host with PowerShell DSC](https://techcommunity.microsoft.com/blog/coreinfrastructureandmanagementblog/configuring-a-hyper-v-host-with-powershell-dsc-part-1/259205) - DSC integration patterns (MEDIUM)
- [Microsoft Hyper-V PowerShell Automation - Packt Publishing](https://www.packtpub.com/en-us/product/microsoft-hyper-v-powershell-automation-9781784392208) - PowerShell automation best practices (MEDIUM)
- [AutomatedLab Tutorial Part 1](https://devblogs.microsoft.com/scripting/automatedlab-tutorial-part-1-introduction-to-automatedlab/) - Introduction to lab automation concepts (HIGH)
- [Hyper-V Automation: PowerShell, SCVMM, and Cloud](https://www.eryph.io/guides/958273-hyper-v-automation-powershell) - Architecture comparison (LOW)
- [Active Directory Lab with Hyper-V and PowerShell](https://www.ired.team/offensive-security-experiments/active-directory-kerberos-abuse/active-directory-lab-with-hyper-v-and-powershell) - Simple lab patterns (MEDIUM)
- [Spin Up Complex Labs in Minutes with PowerShell](https://www.linkedin.com/posts/anilmahadev_automatedlab-activity-7402940175816810496-x5qm) - Modern lab automation approaches (LOW)
- [Engineering Change Enablement for Hyper-V Virtualization](https://medium.com/@leoyeh.me/engineering-change-enablement-for-hyper-v-virtualization-a-technical-lifecycle-approach-e473afb8370e) - Lifecycle patterns (MEDIUM)

---
*Architecture research for: SimpleLab - PowerShell Hyper-V Lab Automation*
*Researched: 2026-02-09*
