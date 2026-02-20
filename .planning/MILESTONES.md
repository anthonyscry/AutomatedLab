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
