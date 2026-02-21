# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.
**Current focus:** v1.6 Lab Lifecycle & Security Automation — Phase 27: PowerSTIG DSC Baselines (gap closure complete)

## Current Position

Phase: 27 of 29 (PowerSTIG DSC Baselines)
Plan: 5 of 5 (complete — gap closure plan)
Status: Phase complete (all gaps closed)
Last activity: 2026-02-20 — Phase 27 Plan 05 complete (PowerSTIG DSC MOF compilation implemented, exceptions wired, stale duplicate removed, 25 tests passing)

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
- [Phase 27-05]: DSC Configuration keyword placed inside here-string evaluated via Invoke-Expression on remote VM — avoids ParseException on Linux/non-DSC test hosts where Configuration keyword is unsupported
- [Phase 27-05]: PowerSTIG exception hashtable uses ValueData='' skip marker pattern; compile+apply in single Invoke-Command -ComputerName session to avoid MOF file transfer

### Pending Todos

None

### Blockers/Concerns

None — Phase 27 gap closure complete. PowerSTIG OsVersion strings should be validated against installed module's StigData/Processed/ on actual Windows VMs before first real deploy.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 27-05-PLAN.md (PowerSTIG DSC MOF compilation gap closure, 25 tests passing)
Resume file: None

---
*State initialized: 2026-02-17 for v1.1 milestone*
*Last updated: 2026-02-20 after Phase 27 Plan 05 gap closure completion*
