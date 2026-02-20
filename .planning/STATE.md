# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-19)

**Core value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.
**Current focus:** v1.3 Lab Scenarios & Operator Tooling — Phase 17: GUI Dashboard Enhancements

## Current Position

Phase: 17 (GUI Dashboard Enhancements) — fourth of 4 phases in v1.3
Plan: 01 complete (2 plans in phase)
Status: In progress
Last activity: 2026-02-20 — Completed 17-01 (Dashboard Health Banner, Resources, Bulk Actions)

Progress: [██████████████████████████████████████░░] 95% (v1.3: Phase 14-16 complete, Phase 17 plan 1/2)

## Performance Metrics

**v1.0 Brownfield Hardening & Integration:**
- 6 phases, 25 plans, 56 requirements

**v1.1 Production Robustness:**
- 4 phases, 13 plans, 19 requirements

**v1.2 Delivery Readiness:**
- 3 phases, 16 plans, 11 requirements
- 847+ Pester tests passing

**v1.3 Lab Scenarios & Operator Tooling:**
- 4 phases, 14 requirements
- Phase 14 Plan 01: 2 tasks, 6 files, 2min, 48 Pester tests
- Phase 14 Plan 02: 2 tasks, 4 files, 2min, 25 integration tests
- Phase 15 Plan 01: 2 tasks, 3 files, 3min, 37 Pester tests
- Phase 15 Plan 02: 2 tasks, 3 files, 2min, 17 integration tests
- Phase 16 Plan 01: 2 tasks, 3 files, 3min, 17 Pester tests
- Phase 16 Plan 02: 2 tasks, 3 files, 2min, 15 integration tests
- Phase 17 Plan 01: 2 tasks, 2 files, 2min

## Accumulated Context

### Decisions

Full log in PROJECT.md Key Decisions table.

- Phase 14-01: Role-based disk estimation lookup (DC=80GB, SQL=100GB, IIS=60GB, Client=60GB, Ubuntu=40GB, default=60GB)
- Phase 14-01: VM definition PSCustomObject shape matches Get-ActiveTemplateConfig for Deploy.ps1 compatibility
- Phase 14-02: Scenario parameter passed conditionally via PSBoundParameters.ContainsKey to avoid empty strings
- Phase 14-02: Scenario override takes precedence over active template in Deploy.ps1
- Phase 15-01: CPU check uses Warn (not Fail) since VMs can share CPU time
- Phase 15-01: Get-WindowsOptionalFeature stub in tests for cross-platform Pester compatibility
- Phase 15-02: Validate action uses PSBoundParameters.ContainsKey for conditional Scenario passthrough
- Phase 15-02: Pre-deploy validation throws to halt deployment on failure (consistent with Deploy.ps1 pattern)
- Phase 15-02: Compact inline format for pre-deploy check summary, detailed output only for failures
- Phase 16-01: Per-snapshot try/catch in Remove-LabStaleSnapshots so one failure does not block others
- Phase 16-01: OverallStatus enum OK/Partial/NoStale for structured CLI consumption
- Phase 16-01: Hyper-V cmdlet stubs in tests for cross-platform Pester compatibility
- Phase 16-02: PruneDays defaults to 7 inside action block via PSBoundParameters.ContainsKey
- Phase 16-02: Lab-Status.ps1 try/catch fallback to Get-VMSnapshot when inventory function unavailable
- Phase 16-02: IndexOf-based block extraction in tests avoids fragile multi-line regex
- Phase 17-01: Health banner background uses FromRgb color construction for PS 5.1 compatibility
- Phase 17-01: Resource display shows VM-assigned RAM plus host free RAM rather than total host RAM
- Phase 17-01: Bulk actions iterate vmNames with per-VM try/catch to avoid one failure stopping all

### Pending Todos

- None

### Blockers/Concerns

- None currently.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 17-01-PLAN.md
Resume file: None

---
*State initialized: 2026-02-17 for v1.1 milestone*
*Last updated: 2026-02-20 after 17-01 plan execution*
