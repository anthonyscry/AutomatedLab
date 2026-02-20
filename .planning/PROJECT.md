# AutomatedLab

## What This Is

A PowerShell-based Windows lab automation tool that provisions Hyper-V virtual machines for domain and role scenarios, usable through CLI, GUI, and module APIs.

## Core Value

Every function handles errors explicitly, surfaces clear diagnostics, and stays modular enough that each piece can be tested and maintained independently.

## Current Milestone: v1.2 Delivery Readiness

**Goal:** Prepare AutomatedLab for reliable operation and shipping by improving documentation, release automation, and public surface test coverage.

**Target features:**
- Publish and validate operator-focused documentation for all core workflows
- Add CI/CD checks and release automation with quality gates
- Expand coverage for Public function behavior and regression scenarios

## Requirements

### Validated

- ✓ v1.1 Production Robustness complete (Phases 7-10) — all 19 requirements
- ✓ 837 Pester tests passing before final v1.1 hardening, then 847 passing after Phase 10
- ✓ 39 + 28 function families modularized or tested for isolation
- ✓ 47 functions exported consistently via .psd1 and .psm1
- ✓ Out-Null replaced where suppressive behavior blocked diagnostics
- ✓ **DOC-01**: README refreshed + GETTING-STARTED.md + 22 entry-doc Pester tests — Phase 11
- ✓ **DOC-02**: LIFECYCLE-WORKFLOWS.md (326 lines) with expected outcomes per workflow — Phase 11
- ✓ **DOC-03**: RUNBOOK-ROLLBACK.md expanded to 410+ lines with 6 failure scenarios — Phase 11
- ✓ **DOC-04**: All 35+ Public functions have complete help; repo-wide quality gate enforced — Phase 11

### Active

- [ ] **CICD-01**: PR pipeline runs full Pester suite with clear diagnostics on failure
- [ ] **CICD-02**: PowerShell ScriptAnalyzer runs with project-appropriate rules
- [ ] **CICD-03**: Release automation performs build, tests, version bump, and artifact validation
- [ ] **CICD-04**: PowerShell Gallery publish workflow uses controlled permissions and artifact checks
- [ ] **TEST-01**: Unit tests added for 20+ untested Public functions
- [ ] **TEST-02**: Coverage reporting and minimum coverage thresholds are enforced in CI
- [ ] **TEST-03**: Smoke E2E suite validates key bootstrap/deploy/teardown path

### Out of Scope

- New lab features beyond v1.1 scope — deferred to v1.3
- Deep performance optimization and VM throughput tuning — correctness and reliability first
- Linux VM behavior expansion — maintain compatibility, but keep no new Linux feature work
- Cloud or container backend support — keep Hyper-V local only

## Context

- v1.0 established baseline automation for lifecycle, roles, GUI integration, and multi-host coordination.
- v1.1 closed production robustness gaps and stabilized modular foundations.
- Deferred capabilities from earlier planning now fall under v1.2 as delivery-readiness work.

## Constraints

- **PowerShell 5.1**: Must remain compatible with Windows PowerShell 5.1.
- **No behavior drift**: Work should not change runtime behavior unless required by this milestone.
- **No new provisioning features**: Feature expansion starts in later milestones.
- **Single developer**: Keep changes maintainable and easy to review.
- **Windows only**: Hyper-V host is Windows 10/11 Pro or Server.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Extract inline functions before broad refactors | Enables unit testing and safer extraction | ✓ completed in v1.1
| Add try-catch to all critical functions before optimization | Prevents silent failures during complex operations | ✓ completed in v1.1
| Replace Out-Null in operational paths with diagnostic-preserving patterns | Improves support and debugging quality | ✓ completed in v1.1
| Move remaining backlog to v1.2 delivery-readiness work | Keeps core behavior stable before expanding scope | ✓ v1.1 complete, v1.2 started
| Docs-first before CI/CD | Stable docs enable CI gate tests and onboarding before automation | ✓ Phase 11 complete
| Repo-wide help quality gate | Pester test enforces .SYNOPSIS/.DESCRIPTION/.EXAMPLE on all Public/ | ✓ Prevents help drift

---
*Last updated: 2026-02-20 after Phase 11*
