# AutomatedLab

## What This Is

A PowerShell-based Windows lab automation tool that provisions Hyper-V virtual machines for domain and role scenarios, usable through CLI, GUI, and module APIs. Ships with full operator documentation, CI/CD pipelines, and comprehensive test coverage.

## Core Value

Every function handles errors explicitly, surfaces clear diagnostics, and stays modular enough that each piece can be tested and maintained independently.

## Current Milestone: v1.3 Lab Scenarios & Operator Tooling

**Goal:** Make labs easier to create and manage by providing scenario templates, configuration validation, snapshot lifecycle tools, and GUI dashboard improvements.

**Target features:**
- Pre-built lab scenario templates (basic AD, security testing, multi-tier app)
- Configuration validation with guided diagnostics before deployment
- Snapshot lifecycle management (list, compare, prune stale snapshots)
- GUI dashboard improvements for operational visibility

## Current State

**Version:** v1.3 in progress (started 2026-02-19)
**Tests:** 847+ Pester tests passing (unit + integration + E2E smoke)
**CI:** GitHub Actions PR pipeline (Pester + ScriptAnalyzer), release automation
**Docs:** README, Getting Started guide, lifecycle workflows, rollback runbook, full Public function help

All 3 prior milestones shipped:
- v1.0 Brownfield Hardening & Integration (6 phases, 25 plans)
- v1.1 Production Robustness (4 phases, 13 plans)
- v1.2 Delivery Readiness (3 phases, 16 plans)

## Requirements

### Validated

- ✓ v1.0: 56 requirements — lifecycle, security, roles, GUI, multi-host (Phases 1-6)
- ✓ v1.1: 19 requirements — error handling, orchestrator extraction, diagnostics (Phases 7-10)
- ✓ v1.2 DOC-01 through DOC-04: Full documentation suite with quality gates (Phase 11)
- ✓ v1.2 CICD-01 through CICD-04: CI/CD pipelines and release automation (Phase 12)
- ✓ v1.2 TEST-01 through TEST-03: Public function tests, coverage reporting, E2E smoke (Phase 13)

### Active

- [ ] Lab scenario templates for common use cases
- [ ] Configuration validation with guided diagnostics
- [ ] Snapshot lifecycle management tools
- [ ] GUI dashboard operational improvements

### Out of Scope

- Azure/cloud backend support — Hyper-V local only
- Multi-domain forest scenarios — niche, document manual approach
- Custom role plugin system — validate core use cases first
- Linux VM behavior expansion — maintain compatibility only
- Deep performance optimization — correctness and reliability first

## Context

- v1.0 established baseline automation for lifecycle, roles, GUI integration, and multi-host coordination
- v1.1 closed production robustness gaps and stabilized modular foundations
- v1.2 delivered shipping infrastructure: docs, CI/CD, and test coverage
- v1.3 focuses on reducing friction for new users and improving daily operator experience
- Lab-Config.ps1 drives all lab topology — scenario templates will generate valid configs for common patterns

## Constraints

- **PowerShell 5.1**: Must remain compatible with Windows PowerShell 5.1
- **Single developer**: Keep changes maintainable and easy to review
- **Windows only**: Hyper-V host is Windows 10/11 Pro or Server

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Extract inline functions before broad refactors | Enables unit testing and safer extraction | ✓ v1.1 |
| Add try-catch to all critical functions | Prevents silent failures | ✓ v1.1 |
| Replace Out-Null with diagnostic-preserving patterns | Improves debugging | ✓ v1.1 |
| Docs-first before CI/CD | Stable docs enable CI gates and onboarding | ✓ v1.2 |
| Repo-wide help quality gate | Pester enforces help on all Public/ | ✓ v1.2 |
| GitHub Actions on windows-latest | Hyper-V module compatibility in CI | ✓ v1.2 |
| Tag-based releases with .psd1 version source | Clean release flow | ✓ v1.2 |
| Simulation-mode E2E testing | Exercises orchestration without Hyper-V | ✓ v1.2 |

---
*Last updated: 2026-02-19 after v1.3 milestone start*
