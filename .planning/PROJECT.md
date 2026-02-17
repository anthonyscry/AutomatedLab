# AutomatedLab

## What This Is

A PowerShell-based Windows lab automation tool that provisions Hyper-V virtual machines (DC, Server, Workstation) with networking, domain join, and role-based configuration — controllable via CLI menu, GUI, or direct script invocation.

## Core Value

Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.

## Current Milestone: v1.1 Production Robustness

**Goal:** Every function handles errors explicitly, the orchestrator is modular and testable, and all 10 known production gaps are closed — so deploys either succeed or explain exactly why they failed.

**Target features:**
- Fix all 10 documented production gaps (security S1-S4, reliability R1-R4, maintainability M1-M2)
- Extract 31 inline functions from OpenCodeLab-App.ps1 to Private/ helpers
- Add try-catch error handling to all 39 functions currently missing it
- Module export audit and reconciliation
- Replace Out-Null with Write-Verbose for diagnostic visibility

## Requirements

### Validated

- ✓ PowerShell module with 107 functions across Public/Private — v1.0
- ✓ WPF GUI with Dashboard, Actions, Logs, Settings, Customize views — v1.0
- ✓ CLI orchestrator with 25+ actions — v1.0
- ✓ Quick mode with auto-heal and LabReady snapshot restoration — v1.0
- ✓ Role-based VM provisioning (DC, SQL, IIS, WSUS, DHCP, FileServer, etc.) — v1.0
- ✓ Template system for customizable VM deployment — v1.0
- ✓ Network infrastructure (vSwitch, NAT, static IPs) — v1.0
- ✓ Domain configuration (DC promotion, DNS, domain join) — v1.0
- ✓ Unified $GlobalLabConfig with fail-fast validation — v1.0
- ✓ Security hardening (password chain, SSH known_hosts, checksum, log scrubbing) — v1.0
- ✓ GUI-CLI feature parity — v1.0
- ✓ Multi-host coordination (dispatch, scoped tokens, transient failure classification) — v1.0
- ✓ 542 Pester tests passing — v1.0
- ✓ Security gaps S1-S4 closed with regression tests (24 tests) — Phase 7
- ✓ Reliability gaps R1-R4 closed with regression tests (24 tests) — Phase 7
- ✓ 566 Pester tests passing — Phase 7

### Active

- [ ] 31 inline functions extracted from OpenCodeLab-App.ps1 to Private/ helpers
- [ ] All 39 functions without try-catch get explicit error handling
- [ ] Module export list reconciled between .psd1 and .psm1
- [ ] Out-Null replaced with Write-Verbose across codebase
- [ ] Orchestrator is modular — each extracted helper independently testable

### Out of Scope

- New features or capabilities — this is about robustness
- Documentation overhaul — deferred to v1.2
- CI/CD pipeline — deferred to v1.2
- Test coverage for untested Public functions — deferred to v1.2
- Performance optimization — correctness first
- Linux VM active testing — keep code intact but don't prioritize

## Context

- v1.0 Hardening milestone complete (2026-02-17): 6 phases, 56 requirements, 542 tests
- Remaining production gaps documented in `docs/plans/2026-02-16-remaining-production-gaps-design.md`
- OpenCodeLab-App.ps1 is 2,012 lines with 31 inline functions — extraction is prerequisite for testability
- 39 functions (28 Private, 11 Public) lack try-catch error handling
- 65 Out-Null instances suppress diagnostic information
- Module export mismatch between SimpleLab.psd1 (47 functions) and SimpleLab.psm1

## Constraints

- **PowerShell 5.1**: Must remain compatible with Windows PowerShell 5.1
- **Single developer**: Code must be understandable and maintainable
- **Windows only**: Hyper-V host is always Windows 10/11 Pro or Server
- **Admin required**: Most operations require elevated privileges
- **No behavior changes**: Extraction and error handling must not change observable behavior

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Extract inline functions before adding error handling | Can't properly test inline functions; extraction enables unit testing | — Pending |
| Fix all 10 production gaps, not just security | Reliability gaps (exit 0, missing validation) affect daily use | ✓ 8/10 closed in Phase 7 (S1-S4, R1-R4); M1-M2 in Phases 9-10 |
| Replace Out-Null with Write-Verbose | Suppressed output hides diagnostics; Verbose is opt-in | — Pending |
| Clean up dead code and archive | Reduce repo noise and search pollution | ✓ v1.0 |
| Unified config to $GlobalLabConfig | Eliminated dual config system, fail-fast validation | ✓ v1.0 |
| Standardized helper sourcing | Lab-Common.ps1 dynamic discovery | ✓ v1.0 |
| Mandatory download checksum validation | Fail if no hash configured | ✓ v1.0 |
| Credential scrubbing in log output | Multi-layer scrubber wired into Write-RunArtifact | ✓ v1.0 |

---
*Last updated: 2026-02-17 after Phase 7*
