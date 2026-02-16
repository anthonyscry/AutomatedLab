# AutomatedLab — Hardening & Integration

## What This Is

A PowerShell-based Windows lab automation tool that provisions Hyper-V virtual machines (DC, Server, Workstation) with networking, domain join, and role-based configuration — controllable via CLI menu, GUI, or direct script invocation. This milestone focuses on making every existing feature actually work end-to-end.

## Core Value

Every button, menu option, and CLI action works reliably from start to finish — bootstrap through teardown, in both GUI and CLI, on a single host or coordinated across multiple hosts.

## Requirements

### Validated

- ✓ PowerShell module with 107 functions across Public/Private — existing
- ✓ WPF GUI with Dashboard, Actions, Logs, Settings, Customize views — existing
- ✓ CLI orchestrator with 25+ actions (deploy, teardown, health, status, etc.) — existing
- ✓ Quick mode with auto-heal and LabReady snapshot restoration — existing
- ✓ Role-based VM provisioning (DC, SQL, IIS, WSUS, DHCP, FileServer, etc.) — existing
- ✓ Template system for customizable VM deployment — existing
- ✓ Network infrastructure (vSwitch, NAT, static IPs) — existing
- ✓ Domain configuration (DC promotion, DNS, domain join) — existing
- ✓ Pester test suite with 28 test files — existing

### Active

- [ ] All CLI actions execute without errors (deploy, teardown, bootstrap, health, status, etc.)
- [ ] All GUI buttons and views function correctly (Dashboard polling, Actions execution, Customize templates, Settings persistence)
- [ ] Bootstrap → Deploy → Use → Teardown lifecycle completes end-to-end
- [ ] Quick mode restore and auto-heal work reliably
- [ ] Multi-host coordinator/dispatch system functions correctly
- [ ] All 16 LabBuilder roles provision successfully
- [ ] Error handling is consistent — no silent failures or unhandled exceptions
- [x] Security hardened — password resolution chain, SSH known_hosts, checksum validation, log scrubbing — Phase 2
- [x] Configuration system is unified (resolve dual hashtable/legacy variable pattern) — Phase 1
- [x] Dead code and archive artifacts cleaned up — Phase 1
- [ ] GUI and CLI feature parity — everything accessible from both interfaces

### Out of Scope

- New features or capabilities — this is about making existing features work
- Linux VM active testing — keep code intact but don't prioritize (LIN1 Ubuntu)
- Mobile or web interface — desktop WPF GUI only
- Cloud/Azure integration — local Hyper-V only
- Performance optimization — correctness first

## Context

- Codebase has 104 functions (3 dead functions removed in Phase 1) but hasn't been tested end-to-end recently
- Codebase mapping (2026-02-16) identified: hardcoded passwords, error handling gaps, large orchestration scripts (1500-2000 lines)
- Helper sourcing standardized to Lab-Common.ps1 dynamic discovery with fail-fast (Phase 1)
- $GlobalLabConfig is now single source of truth with validation on load (Phase 1)
- GUI crash logs indicate runtime issues in view switching and template application
- Multi-host coordinator infrastructure exists but hasn't been integration-tested
- `.archive/` directory contains deprecated code inflating repository size
- Test coverage artifacts (coverage.xml) and LSP tools committed to repo

## Constraints

- **PowerShell 5.1**: Must remain compatible with Windows PowerShell 5.1 (Join-Path 2-arg limit, etc.)
- **Single developer**: One person maintaining — code must be understandable and maintainable
- **Windows only**: Hyper-V host is always Windows 10/11 Pro or Server
- **Admin required**: Most operations require elevated privileges

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Include multi-host coordinator | User wants it working, infrastructure already exists | — Pending |
| Linux VMs deprioritized | Keep code but don't actively test — Windows flows first | — Pending |
| Brownfield hardening, not new features | 107 functions exist but need integration testing and wiring | — Pending |
| Clean up dead code and archive | Reduce repo noise and search pollution | ✓ Phase 1 |
| Unified config to $GlobalLabConfig | Eliminated dual config system, fail-fast validation | ✓ Phase 1 |
| Standardized helper sourcing | Lab-Common.ps1 dynamic discovery, removed $OrchestrationHelperPaths | ✓ Phase 1 |
| Template validation throws on invalid data | No soft errors, shared Test-LabTemplateData helper | ✓ Phase 1 |
| Password resolution with interactive fallback | Keep default with warning, prompt when missing, hardcoded env var names | ✓ Phase 2 |
| SSH accept-new with lab-specific known_hosts | Replaced UserKnownHostsFile=NUL, auto-clear on teardown | ✓ Phase 2 |
| Mandatory download checksum validation | Removed conditional bypass, fail if no hash configured | ✓ Phase 2 |
| Credential scrubbing in log output | Protect-LabLogString multi-layer scrubber wired into Write-RunArtifact | ✓ Phase 2 |

---
*Last updated: 2026-02-16 after Phase 2*
