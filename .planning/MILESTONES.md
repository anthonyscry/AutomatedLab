# Milestones: AutomatedLab

## Completed Milestones

### v1.0 — Brownfield Hardening & Integration (2026-02-16 → 2026-02-17)

**Goal:** Every button, menu option, and CLI action works reliably from start to finish — bootstrap through teardown, in both GUI and CLI, on a single host or coordinated across multiple hosts.

**Phases:** 1–6
**Requirements:** 56/56 complete
**Tests:** 542 passing, 0 failing

**What shipped:**
- Cleanup & config foundation (dead code removal, unified $GlobalLabConfig, standardized helper sourcing)
- Security hardening (password resolution chain, SSH known_hosts, checksum validation, log scrubbing)
- Core lifecycle integration (bootstrap → deploy → teardown with error handling, string interpolation fixes)
- Role provisioning (all 16 LabBuilder roles with try-catch, prereq validation, post-install verification)
- GUI integration (action parity, timer lifecycle, theme-safe colors, settings persistence, customize hardening)
- Multi-host coordination (host inventory, dispatch routing, scoped tokens, transient failure classification, E2E integration)

**Key decisions:**
- Aggressive dead code removal without deprecation period
- $GlobalLabConfig as single source of truth with fail-fast validation
- Mandatory subexpression syntax for nested config interpolation
- SSH accept-new with lab-specific known_hosts
- Mandatory download checksum validation

**Last phase number:** 6

### v1.1 — Production Robustness (2026-02-17 → 2026-02-17)

**Goal:** Close production gaps in security, reliability, orchestration, error handling, and diagnostics.

**Phases:** 7–10
**Requirements:** 19/19 complete
**Tests:** 847 passing

**What shipped:**
- Security & reliability gap closure (S1-S4, R1-R4)
- Orchestrator extraction and helper modularization
- Private/Public error handling completion
- Module export and diagnostic cleanup

**Key decisions:**
- Stabilize foundation before adding new feature capabilities
- Prioritize behavior-safe refactors and test coverage for each phase

**Last phase number:** 10

### v1.2 — Delivery Readiness (2026-02-18 → 2026-02-20)

**Goal:** Prepare for safe shipping and adoption by improving delivery docs, release automation, and public API test coverage.

**Phases:** 11–13 (3 phases, 16 plans)
**Requirements:** 11/11 complete
**Tests:** 847+ passing (expanded with 47 Public function tests + E2E smoke)

**What shipped:**
- README refresh, GETTING-STARTED.md onboarding guide, lifecycle workflows guide, rollback runbook (Phase 11)
- Complete help comments for all 35+ Public functions with repo-wide quality gate (Phase 11)
- Runtime docs validation script with evidence report and 22 Pester contract tests (Phase 11)
- GitHub Actions PR test pipeline (Pester on Windows runner) and ScriptAnalyzer lint workflow (Phase 12)
- Release and Gallery publish automation with controlled permissions (Phase 12)
- Unit tests for 47 previously untested Public functions with shared Hyper-V mock infrastructure (Phase 13)
- Coverage reporting with threshold enforcement in CI (Phase 13)
- E2E smoke test for bootstrap/deploy/teardown lifecycle (Phase 13)

**Key decisions:**
- Docs-first before CI/CD (stable docs enable CI gate tests and onboarding)
- Repo-wide help quality gate (Pester enforces .SYNOPSIS/.DESCRIPTION/.EXAMPLE on all Public/)
- GitHub Actions on windows-latest for Hyper-V module compatibility
- Tag-based releases with SimpleLab.psd1 as version source of truth
- Simulation-mode E2E (mocked Hyper-V layer, exercises full orchestration path)

**Last phase number:** 13

---

### v1.3 — Lab Scenarios & Operator Tooling (2026-02-20 → 2026-02-20)

**Goal:** Reduce friction with scenario templates, pre-deployment validation, snapshot tools, and dashboard improvements.

**Phases:** 14–17 (4 phases, 8 plans)
**Requirements:** 14/14 complete
**Tests:** ~189 new tests (unit + integration + E2E smoke)

**What shipped:**
- Scenario templates as JSON files with CLI integration and resource estimation (Phase 14)
- Pre-deployment validation with guided diagnostics (Phase 15)
- Snapshot inventory and pruning with ShouldProcess safety (Phase 16)
- Dashboard health banner, resource summary, and bulk actions (Phase 17)

**Key decisions:**
- Scenario templates as JSON files — new scenarios via file drop, no code changes
- No ValidateSet on -Scenario — runtime validation auto-discovers templates
- CPU check warns not fails — VMs can share CPU time
- ShouldProcess on snapshot pruning — -WhatIf safety for destructive operations

**Last phase number:** 17

### v1.4 — Configuration Management & Reporting (2026-02-20 → 2026-02-20)

**Goal:** Configuration persistence, deployment history tracking, GUI log viewing, and portable lab packages.

**Phases:** 18–21 (4 phases, 8 plans)
**Requirements:** 13/13 complete
**Tests:** 74 new Pester tests

**What shipped:**
- Named configuration profiles with save, load, list, delete CRUD operations (Phase 18)
- Run history tracking via Get-LabRunHistory wrapping existing artifact infrastructure (Phase 19)
- GUI log viewer with DataGrid, action-type filtering, and text file export (Phase 20)
- Lab export/import with self-contained JSON packages and multi-field integrity validation (Phase 21)

**Key decisions:**
- Profiles as JSON in .planning/profiles/ following template storage pattern
- $Config parameter not $GlobalLabConfig for testability
- Get-LabRunHistory wraps existing Write-LabRunArtifacts — no new logging infrastructure
- ISO 8601 string sort for run ordering
- Cached run history with filter-without-reload in GUI
- Import validates all fields before applying, collecting errors
- ConvertTo-PackageHashtable naming avoids collision with Load-LabProfile

**Last phase number:** 21


### v1.5 — Advanced Scenarios & Multi-OS (2026-02-20 → 2026-02-21)

**Goal:** Custom role templates, complex networking topologies, and full Linux VM parity with mixed OS integration.

**Phases:** 22–25 (4 phases, 8 plans)
**Requirements:** 16/16 complete
**Tests:** ~226 new Pester tests

**What shipped:**
- Custom role template engine — JSON-defined roles with schema validation, auto-discovery, and full LabBuilder integration (Phase 22)
- Multi-switch networking — named vSwitches with VLAN tagging, per-VM switch assignment, pairwise subnet overlap detection, multi-subnet routing (Phase 23)
- Linux VM full parity — snapshot inventory discovers all Linux VMs, profile metadata, SSH retry with configurable backoff (Phase 24)
- CentOS Stream 9 support — new role with cloud-init NoCloud provisioning and dnf package management (Phase 24)
- Mixed OS integration — end-to-end scenario template (DC + IIS + Ubuntu + DB), integration tests, lifecycle documentation (Phase 25)

**Key decisions:**
- Custom roles as JSON with warn-and-skip schema validator
- Switches array coexists with flat SwitchName key for backward compat
- Per-VM switch/VLAN via IPPlan hashtable format with plain string fallback
- PSBoundParameters for SSH retry defaults — LabConfig override only when not explicit
- CentOS reuses Invoke-LinuxRoleCreateVM with ISOPattern differentiator
- Static analysis tests validate cross-OS provisioning flow without Hyper-V

**Last phase number:** 25

---

