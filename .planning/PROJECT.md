# AutomatedLab

## What This Is

A PowerShell-based Windows lab automation tool that provisions Hyper-V virtual machines for domain and role scenarios, usable through CLI, GUI, and module APIs. Ships with scenario templates, pre-deployment validation, snapshot management, full operator documentation, CI/CD pipelines, and comprehensive test coverage.

## Core Value

Every function handles errors explicitly, surfaces clear diagnostics, and stays modular enough that each piece can be tested and maintained independently.

## Current State

**Version:** v1.3 shipped (2026-02-20)
**Tests:** 847+ Pester tests passing + ~189 new tests (unit + integration + E2E smoke)
**CI:** GitHub Actions PR pipeline (Pester + ScriptAnalyzer), release automation
**Docs:** README, Getting Started guide, lifecycle workflows, rollback runbook, full Public function help

All 4 milestones shipped:
- v1.0 Brownfield Hardening & Integration (6 phases, 25 plans)
- v1.1 Production Robustness (4 phases, 13 plans)
- v1.2 Delivery Readiness (3 phases, 16 plans)
- v1.3 Lab Scenarios & Operator Tooling (4 phases, 8 plans)

## Requirements

### Validated

- ✓ v1.0: 56 requirements — lifecycle, security, roles, GUI, multi-host (Phases 1-6)
- ✓ v1.1: 19 requirements — error handling, orchestrator extraction, diagnostics (Phases 7-10)
- ✓ v1.2 DOC-01 through DOC-04: Full documentation suite with quality gates (Phase 11)
- ✓ v1.2 CICD-01 through CICD-04: CI/CD pipelines and release automation (Phase 12)
- ✓ v1.2 TEST-01 through TEST-03: Public function tests, coverage reporting, E2E smoke (Phase 13)
- ✓ v1.3 TMPL-01 through TMPL-05: Scenario templates with CLI integration and resource estimation (Phase 14)
- ✓ v1.3 CONF-01 through CONF-03: Pre-deployment validation with guided diagnostics (Phase 15)
- ✓ v1.3 SNAP-01 through SNAP-03: Snapshot inventory, pruning, and status integration (Phase 16)
- ✓ v1.3 DASH-01 through DASH-03: Dashboard health banner, resource summary, bulk actions (Phase 17)
- ✓ v1.4 PROF-01 through PROF-04: Named configuration profiles with save, load, list, delete (Phase 18)
- ✓ v1.4 HIST-01 through HIST-03: Run history tracking with automatic logging and query cmdlet (Phase 19)
- ✓ v1.4 LOGV-01 through LOGV-03: GUI log viewer with filtering and export (Phase 20)

### Active

v1.4 Configuration Management & Reporting:
- Named configuration profiles (save, load, list, delete lab configs)
- Run history tracking (deployment logs, outcomes, timestamps)
- Enhanced GUI log viewer (search, filter, export run logs)
- Lab export/import (portable lab definition packages)

### Out of Scope

- Azure/cloud backend support — Hyper-V local only
- Multi-domain forest scenarios — niche, document manual approach
- Custom role plugin system — validate core scenario templates first
- Custom scenario builder GUI wizard — CLI + JSON templates sufficient
- Snapshot diff/comparison — list and prune sufficient for operator needs
- Linux VM behavior expansion — maintain compatibility only
- Deep performance optimization — correctness and reliability first

## Context

- v1.0 established baseline automation for lifecycle, roles, GUI integration, and multi-host coordination
- v1.1 closed production robustness gaps and stabilized modular foundations
- v1.2 delivered shipping infrastructure: docs, CI/CD, and test coverage
- v1.3 reduced friction with scenario templates, validation, snapshot tools, and dashboard improvements
- Lab-Config.ps1 drives all lab topology — scenario templates generate valid configs for common patterns
- Project is mature across 4 milestones with comprehensive test coverage and documentation

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
| Scenario templates as JSON files | New scenarios via file drop, no code changes | ✓ v1.3 |
| No ValidateSet on -Scenario | Runtime validation auto-discovers templates | ✓ v1.3 |
| CPU check warns not fails | VMs can share CPU time, only RAM/disk are hard constraints | ✓ v1.3 |
| ShouldProcess on snapshot pruning | -WhatIf safety for destructive operations | ✓ v1.3 |
| Profiles as JSON in .planning/profiles/ | Follows template storage pattern, no new infrastructure | ✓ v1.4 |
| $Config parameter not $GlobalLabConfig | Keeps profile functions testable and side-effect-free | ✓ v1.4 |
| Recursive PSCustomObject-to-hashtable | Handles JSON round-trip for PS 5.1 ConvertFrom-Json | ✓ v1.4 |
| Get-LabRunHistory wraps existing helpers | No new logging infra needed, reuses Write-LabRunArtifacts | ✓ v1.4 |
| ISO 8601 string sort for run ordering | Avoids DateTime parsing overhead and PS version differences | ✓ v1.4 |
| Cached run history with filter-without-reload | Avoids repeated disk reads when switching action filter | ✓ v1.4 |
| Raw string matching for GUI tests | Validates XAML structure without WPF runtime dependency | ✓ v1.4 |

---
*Last updated: 2026-02-20 after Phase 20*
