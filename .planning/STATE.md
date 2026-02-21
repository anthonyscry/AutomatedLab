# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.
**Current focus:** v1.6 Lab Lifecycle & Security Automation — Phase 27: PowerSTIG DSC Baselines

## Current Position

Phase: 27 of 29 (PowerSTIG DSC Baselines)
Plan: 4 of 4 (complete)
Status: Phase complete
Last activity: 2026-02-21 — Phase 27 Plan 04 complete (Public STIG cmdlets + PostInstall integration, 22 new tests, 97 total STIG tests)

Progress: [██░░░░░░░░] 20% (v1.6)

## Performance Metrics

**v1.0 Brownfield Hardening & Integration:** 6 phases, 25 plans, 56 requirements
**v1.1 Production Robustness:** 4 phases, 13 plans, 19 requirements
**v1.2 Delivery Readiness:** 3 phases, 16 plans, 11 requirements
**v1.3 Lab Scenarios & Operator Tooling:** 4 phases, 8 plans, 14 requirements
**v1.4 Configuration Management & Reporting:** 4 phases, 8 plans, 13 requirements
**v1.5 Advanced Scenarios & Multi-OS:** 4 phases, 8 plans, 16 requirements (~226 new tests)

## Accumulated Context

### Decisions

Full log in PROJECT.md Key Decisions table. Key decisions for v1.6:
- STIG config block added to GlobalLabConfig after TTL block; Enabled=$false by default
- Get-LabSTIGConfig uses ContainsKey guards matching Phase 26 TTL pattern; Exceptions defaults to @{} not null
- Get-LabSTIGProfile: caller discovers OS version and passes as param — no live VM queries inside helper; StartsWith prefix matching handles full build.revision strings
- Test-PowerStigInstallation: try/catch returns structured PSCustomObject on WinRM failure; Invoke-Command mocked at Pester level for unit tests
- All new features gated by `Enabled = $false` in $GlobalLabConfig — existing behavior unchanged when config keys absent
- STIG compliance uses cache-on-write (.planning/stig-compliance.json) — no live DSC queries on dashboard hot path
- TTL monitoring uses Windows Scheduled Tasks (survives PowerShell session termination), not background jobs
- Dashboard enrichment uses 60-second background runspace + synchronized hashtable — must be designed at phase start, not retrofitted
- DSC modules must install -Scope AllUsers (machine scope) — CurrentUser silently fails under SYSTEM context
- [Phase 27-03]: Side-effect Invoke-Command calls piped to Out-Null — prevents null pipeline leakage from mocks causing PSCustomObject to be wrapped in Object[] array
- [Phase 27-03]: Pester 5: stub missing DSC cmdlets as global: functions in BeforeAll so Pester can mock them on non-Windows test host
- [Phase 27]: Private function renamed to Invoke-LabSTIGBaselineCore to avoid public/private naming collision; Public wrapper uses splatted params to correctly pass no-VMName case
- [Phase 27]: Member server STIG placed in Build-LabFromSelection.ps1 Phase 11.5 — single location covers all current and future member server roles

### Pending Todos

None

### Blockers/Concerns

- Phase 27 (PowerSTIG): PowerSTIG OsVersion string values for Windows Server 2019/2022 must be confirmed by inspecting installed module's StigData/Processed/ directory before MOF compilation scaffold is written — do not hard-code version strings
- Phase 27 (PowerSTIG): SkipRule + SkipRuleType incompatibility (GitHub issue #653) — validate which exception mechanism suits lab use case before finalizing StigExceptions config block schema

## Session Continuity

Last session: 2026-02-21
Stopped at: Completed 27-04-PLAN.md (Public STIG cmdlets + PostInstall integration, 22 new tests)
Resume file: None

---
*State initialized: 2026-02-17 for v1.1 milestone*
*Last updated: 2026-02-21 after Phase 27 Plan 04 completion*
