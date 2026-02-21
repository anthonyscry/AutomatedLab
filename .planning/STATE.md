# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.
**Current focus:** v1.6 Lab Lifecycle & Security Automation — Phase 26: Lab TTL & Lifecycle Monitoring

## Current Position

Phase: 26 of 29 (Lab TTL & Lifecycle Monitoring)
Plan: — of — (not yet planned)
Status: Ready to plan
Last activity: 2026-02-20 — v1.6 roadmap created (18/18 requirements mapped to Phases 26-29)

Progress: [░░░░░░░░░░] 0% (v1.6)

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
- All new features gated by `Enabled = $false` in $GlobalLabConfig — existing behavior unchanged when config keys absent
- STIG compliance uses cache-on-write (.planning/stig-compliance.json) — no live DSC queries on dashboard hot path
- TTL monitoring uses Windows Scheduled Tasks (survives PowerShell session termination), not background jobs
- Dashboard enrichment uses 60-second background runspace + synchronized hashtable — must be designed at phase start, not retrofitted
- DSC modules must install -Scope AllUsers (machine scope) — CurrentUser silently fails under SYSTEM context

### Pending Todos

None

### Blockers/Concerns

- Phase 27 (PowerSTIG): PowerSTIG OsVersion string values for Windows Server 2019/2022 must be confirmed by inspecting installed module's StigData/Processed/ directory before MOF compilation scaffold is written — do not hard-code version strings
- Phase 27 (PowerSTIG): SkipRule + SkipRuleType incompatibility (GitHub issue #653) — validate which exception mechanism suits lab use case before finalizing StigExceptions config block schema

## Session Continuity

Last session: 2026-02-20
Stopped at: v1.6 roadmap created, all 18 requirements mapped, ready to plan Phase 26
Resume file: None

---
*State initialized: 2026-02-17 for v1.1 milestone*
*Last updated: 2026-02-20 after v1.6 roadmap creation*
