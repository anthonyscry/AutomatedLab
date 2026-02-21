# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-21)

**Core value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.
**Current focus:** Planning next milestone (v1.7)

## Current Position

Milestone: v1.6 Lab Lifecycle & Security Automation — COMPLETE
Phase: All phases (26-29) complete
Status: Milestone complete, archived 2026-02-21
Last activity: 2026-02-21 — Phase 29 complete with 28 dashboard tests passing

Progress: [██████████] 100% (v1.6 Milestone)

## Performance Metrics

**v1.0 Brownfield Hardening & Integration:** 6 phases, 25 plans, 56 requirements
**v1.1 Production Robustness:** 4 phases, 13 plans, 19 requirements
**v1.2 Delivery Readiness:** 3 phases, 16 plans, 11 requirements
**v1.3 Lab Scenarios & Operator Tooling:** 4 phases, 8 plans, 14 requirements
**v1.4 Configuration Management & Reporting:** 4 phases, 8 plans, 13 requirements
**v1.5 Advanced Scenarios & Multi-OS:** 4 phases, 8 plans, 16 requirements (~226 new tests)
**v1.6 Lab Lifecycle & Security Automation:** 4 phases, 17 plans, 18 requirements (66 new tests)

**Total: 29 phases, 95 plans, 147 requirements across 7 milestones**

## Accumulated Context

### Decisions

Full log in PROJECT.md Key Decisions table. Key decisions for v1.6:
- TTL defaults to disabled — operator must opt in to auto-suspend
- STIG defaults to disabled — operator must opt in to DISA baselines
- ADMX Enabled defaults to true, CreateBaselineGPO defaults to false — import runs by default, GPOs are opt-in
- TTL monitoring uses Windows Scheduled Tasks (survives PowerShell session termination), not background jobs
- STIG compliance uses cache-on-write (.planning/stig-compliance.json) — no live DSC queries on dashboard hot path
- Dashboard enrichment uses 60-second background runspace + synchronized hashtable — must be designed at phase start
- DSC modules must install -Scope AllUsers (machine scope) — CurrentUser silently fails under SYSTEM context
- Wait-LabADReady gates ADMX/GPO on Get-ADDomain with 120s timeout, 10s retry interval
- STA apartment state required for WPF runspace compatibility
- PowerSTIG exception uses ValueData='' skip marker pattern
- Per-template error isolation for GPO creation — one failure doesn't block others
- Comma-prefix operator (,@()) prevents single-element array unwrapping in PSCustomObject

### Pending Todos

None — v1.6 milestone complete, ready to plan v1.7

### Blockers/Concerns

None

## Session Continuity

Last session: 2026-02-21
Stopped at: Milestone v1.6 completion
Resume file: None

---
*State initialized: 2026-02-17 for v1.1 milestone*
*Last updated: 2026-02-21 after v1.6 milestone completion*
