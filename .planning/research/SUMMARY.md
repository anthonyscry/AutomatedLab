# Project Research Summary

**Project:** SimpleLab
**Domain:** PowerShell Hyper-V Windows Domain Lab Automation
**Researched:** 2026-02-09
**Confidence:** HIGH

## Executive Summary

SimpleLab is a streamlined PowerShell CLI tool for spinning up Windows domain test labs via Hyper-V. Expert consensus indicates that native PowerShell 5.1 with the Hyper-V module is the optimal foundation for this use case — AutomatedLab is overkill for simple 2-3 VM Windows domain labs, adding complexity (ISO detection, disclaimers, role abstraction) without proportional value. The recommended approach is an orchestrator-worker pattern with dedicated scripts for preflight validation, VM provisioning, domain configuration, and health checks — all wrapped in a menu-driven interface for accessibility.

The primary technical risk is silent failures during automation scripts. The most dangerous automation is what doesn't fail loudly when something goes wrong. This must be addressed with structured error handling, validation gates after each critical stage, and automatic rollback to known-good checkpoints. The secondary risk is network configuration drift — Windows' "Default Switch" has unpredictable subnets that break static IPs and NAT configuration. The solution is a dedicated Internal vSwitch with host-side NAT, configured idempotently on every run.

Key differentiators from AutomatedLab include: menu-driven interface for non-PowerShell experts, snapshot-based rollback for quick state restoration, non-interactive mode for CI/CD integration, and health gate validation that prevents broken lab states. Linux VM support should be deferred to v2+ as it introduces a different automation model (cloud-init vs unattended.xml) that complicates the core Windows domain use case.

## Key Findings

### Recommended Stack

PowerShell 5.1 (built into Windows 10/11) with the native Hyper-V module provides complete control over VM lifecycle without third-party dependencies. Windows PowerShell 7.x has limited Hyper-V cmdlet support, making 5.1 the clear choice. For package management, Microsoft.PowerShell.PSResourceGet (1.1.1+) is the future and should replace the deprecated PowerShellGet v2. Supporting libraries include Pester 5.7.1+ for testing, PSFramework 1.13.414+ for structured logging and configuration, and PSScriptAnalyzer for code quality.

**Core technologies:**
- **PowerShell 5.1:** Core scripting engine — Ships with Windows, full Hyper-V module support, mature ecosystem
- **Hyper-V Module (built-in):** VM provisioning and management — Native Windows module, no dependencies, complete Hyper-V control
- **PSResourceGet 1.1.1+:** Package management — Official replacement for PowerShellGet v2, faster and more reliable
- **Pester 5.7.1+:** Testing framework — Essential for validating lab deployment and VM states

**Critical version requirements:**
- Pester 5.x has breaking changes from 4.x — update existing tests
- PSResourceGet requires .NET 4.7.1+ on PS 5.1
- Client Hyper-V has limitations (~100 VMs max) — Server Hyper-V recommended for frequent resets

### Expected Features

**Must have (table stakes):**
- **Single-command build** — Core value prop; users want to type one command and get a working lab
- **AD domain creation** — Windows lab without AD is not a "domain lab" (DC promotion, DNS setup, domain join)
- **VM lifecycle management** — Start, stop, restart VMs is a basic expectation
- **Network configuration** — VMs must communicate (Internal switch, IP assignment, NAT)
- **ISO pre-flight validation** — Build fails silently without proper ISOs
- **Clean teardown** — Users need to reset/start over without manual cleanup
- **Error reporting** — Silent failures are unacceptable
- **Status command** — Show VM states and basic health

**Should have (competitive):**
- **Menu-driven interface** — Non-PowerShell experts can use the tool
- **Snapshot-based rollback** — One command restores clean state (LabReady checkpoint)
- **Non-interactive mode** — Enables automation and CI/CD integration
- **Health gate validation** — Prevents broken lab states with automatic rollback
- **Run artifacts (JSON + text)** — Enables monitoring and audit trails

**Defer (v2+):**
- **Linux VM support** — Different automation model (cloud-init), adds complexity, not essential for Windows domain testing
- **Azure support** — Entirely different platform, doubles surface area
- **Custom role system** — Most users never use extensibility features
- **Multi-domain forests** — Niche requirement, document manual approach instead

### Architecture Approach

The recommended architecture is an orchestrator-worker model with clear separation of concerns. A main entry point (SimpleLab-App.ps1) routes to specialized worker scripts for setup, status, teardown, and rollback. Configuration is centralized in a single file (SimpleLab-Config.ps1) with environment variable overrides. A pipeline pattern with health gates ensures each stage validates before proceeding, with automatic rollback on failure.

**Major components:**
1. **Orchestrator (App.ps1)** — Single entry point, action routing, user interaction menu
2. **Config Manager (Config.ps1)** — Centralized configuration with environment variable overrides
3. **Validator (Preflight.ps1)** — Prerequisite verification (ISOs, Hyper-V, RAM, disk) before deployment
4. **Network Manager** — vSwitch and NAT creation with idempotent configuration
5. **VM Provisioner (Deploy.ps1)** — VM creation, ISO attachment, hardware configuration
6. **Domain Configurer** — DC promotion, domain join, DNS/AD/DHCP setup
7. **Health Checker (Health.ps1)** — Post-deployment validation with structured checks and retry logic
8. **Template Manager** — Snapshot/checkpoint management for fast rebuilds

### Critical Pitfalls

1. **Silent Failures** — Use `Set-StrictMode -Version Latest`, implement structured return objects with required properties, add explicit validation gates after each critical stage, never use `-ErrorAction SilentlyContinue` except for truly non-critical operations

2. **Stale VM State** — Implement aggressive pre-flight cleanup, use multiple retry attempts with exponential backoff for VM removal, kill vmwp.exe worker processes as last resort, use `Try { } Finally { }` blocks to ensure cleanup on failure

3. **vSwitch/NAT Configuration Drift** — Always use dedicated Internal vSwitch (never "Default Switch"), check and recreate vSwitch + NAT idempotently every run, verify host gateway IP is still assigned, validate network connectivity before proceeding

4. **Timeout Mismatches** — Configure timeouts appropriately for target hardware (90+ minutes for DC promotion on resource-constrained hosts), use proper TimeSpan objects instead of integers, document timeout requirements

5. **AD DS Promotion Failures** — Implement explicit AD DS validation after deployment completes, check NTDS service status and AD cmdlet functionality, manually run Install-ADDSForest with recovery logic if validation fails, wait for DC restart and verify services before proceeding

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation (Validation Core)
**Rationale:** Pre-flight checks and error handling must exist before provisioning to prevent silent failures and stale state issues — these are the highest-risk pitfalls identified in research.
**Delivers:** Config management, preflight validation, health checks, status reporting, structured logging
**Addresses:** ISO validation, Hyper-V detection, RAM/disk capacity checks, basic error reporting (from FEATURES.md table stakes)
**Avoids:** Silent failures, stale VM state, ISO detection failures (from PITFALLS.md)
**Stack elements:** PSFramework for logging, Pester for testing, PowerShell 5.1 native cmdlets

### Phase 2: Core Provisioning (Domain Lab)
**Rationale:** Network setup and VM provisioning are the foundation; domain configuration depends on VMs being running and networked properly.
**Delivers:** Network setup (vSwitch + NAT), VM provisioning, AD domain creation, domain join for client VMs
**Uses:** Hyper-V module (New-VM, New-VMSwitch, New-NetNat), PowerShell remoting (Invoke-Command)
**Implements:** Network Manager, VM Provisioner, Domain Configurer architecture components
**Addresses:** Single-command build, AD domain creation, network configuration, VM lifecycle management (from FEATURES.md)
**Avoids:** vSwitch/NAT drift, AD DS promotion failures, connectivity assumptions (from PITFALLS.md)

### Phase 3: Lifecycle Management (Resilience)
**Rationale:** Checkpoint/rollback and health gates depend on having a working lab; these provide self-healing and fast iteration.
**Delivers:** Snapshot management, rollback to LabReady checkpoint, health gate validation with automatic rollback
**Uses:** Checkpoint-VM, Restore-VMSnapshot Hyper-V cmdlets
**Implements:** Template Manager, Health Checker architecture components
**Addresses:** Snapshot-based rollback, health gate validation (from FEATURES.md differentiators)
**Avoids:** No checkpoint strategy, silent failures, manual intervention requirements (from PITFALLS.md)

### Phase 4: Orchestration (User Experience)
**Rationale:** Orchestrator and menu interface tie everything together; built last so all worker scripts are stable first.
**Delivers:** Main orchestrator (App.ps1), menu-driven interface, non-interactive mode flags, run artifacts (JSON + text)
**Implements:** Orchestrator pattern, CLI/UX layer
**Addresses:** Menu-driven interface, non-interactive mode, run artifacts (from FEATURES.md differentiators)
**Avoids:** UX pitfalls (no progress indication, cryptic errors, no confirmation)

### Phase Ordering Rationale

- **Foundation first:** Validation and error handling prevent cascading failures from the start
- **Provisioning second:** Core lab functionality is the value prop; depends on validation working
- **Lifecycle third:** Resilience features (snapshots, rollback) require a working lab to snapshot
- **Orchestration last:** UX layer depends on stable worker scripts; changing workers later would break orchestrator

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 2 (Core Provisioning):** Network configuration specifics (IP assignment, DHCP vs static, DNS forwarding) — many pitfalls identified, needs detailed planning
- **Phase 3 (Lifecycle Management):** Checkpoint strategy (when to snapshot, storage management, rollback triggers) — less documentation on best practices

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Foundation):** Well-documented patterns for preflight checks, structured logging, Pester testing
- **Phase 4 (Orchestration):** Standard PowerShell CLI patterns, menu interfaces are straightforward

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified via Microsoft official docs, Hyper-V module is built-in and well-documented |
| Features | MEDIUM | Based on AutomatedLab analysis and community needs; some subjectivity in prioritization |
| Architecture | HIGH | Verified via AutomatedLab source code, established patterns, existing project analysis |
| Pitfalls | HIGH | Verified via GitHub issues, project code analysis, and community troubleshooting guides |

**Overall confidence:** HIGH

### Gaps to Address

- **Network Configuration Details:** Research identifies vSwitch/NAT as critical but doesn't specify exact IP allocation strategy (DHCP scope, static IPs for DC, how to handle conflicts) — resolve during Phase 2 planning
- **Checkpoint Storage Management:** Research doesn't address storage growth from checkpoints (VHDX expansion) — plan storage limits or cleanup strategy during Phase 3
- **Linux VM Specifics:** If Linux support is added later (v2+), need research on cloud-init NoCloud datasource and CIDATA VHDX generation — currently deferred but gap exists
- **Timeout Tuning:** Research identifies timeout issues but doesn't provide exact values for different hardware tiers — needs empirical testing during implementation

## Sources

### Primary (HIGH confidence)
- Microsoft Learn — PowerShell Overview, Hyper-V PowerShell official documentation
- Microsoft Learn — PSResourceGet GA announcement (Oct 2023)
- AutomatedLab GitHub Repository — Source code, issues, documentation
- AutomatedLab Official Website — Feature documentation and tutorials
- Microsoft Dev Blogs — AutomatedLab Tutorial Part 1 (official)
- Pester GitHub — Official repository, version 5.7.1 (Jan 2025)
- PSFramework Blog — v1.13.414 Release notes (Oct 2025)
- PowerShell Direct — Microsoft Learn official docs (Oct 2025)

### Secondary (MEDIUM confidence)
- AutomatedLab Troubleshooting — Official troubleshooting guide
- Getting Started with AutomatedLab (SysManSquad) — Community guide
- Windows Server 2025 Hyper-V Implementation (LenovoPress) — Technical whitepaper (Apr 2025)
- Building an Effective Active Directory Lab Environment (ADSecurity.org) — Security-focused lab guidance
- Vagrant with Hyper-V Provider (GitHub) — Alternative tool comparison
- Active Directory Lab with Hyper-V and PowerShell (ired.team) — Simple lab patterns

### Tertiary (LOW confidence)
- Building an Active Directory/Windows Server Lab (blog.sonnes.cloud) — Blog post, verified with official docs
- Reddit: Hyper-V Automation Tools Discussion — Community discussion
- Medium: Windows Active Directory 101 — Medium post, general practices only
- LinkedIn: Spin Up Complex Labs in Minutes — Social media post, limited detail

---
*Research completed: 2026-02-09*
*Ready for roadmap: yes*
