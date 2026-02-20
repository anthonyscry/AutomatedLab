# Roadmap: AutomatedLab

## Milestones

- ✅ **v1.0 Brownfield Hardening & Integration** - Phases 1-6 (shipped 2026-02-17)
- ✅ **v1.1 Production Robustness** - Phases 7-10 (shipped 2026-02-17)
- ✅ **v1.2 Delivery Readiness** - Phases 11-13 (shipped 2026-02-20)
- **v1.3 Lab Scenarios & Operator Tooling** - Phases 14-17 (in progress)

## Phases

<details>
<summary>✅ v1.0 Brownfield Hardening & Integration (Phases 1-6) - SHIPPED 2026-02-17</summary>

- [x] Phase 1: Cleanup & Config Foundation (4/4 plans) — completed 2026-02-16
- [x] Phase 2: Security Hardening (3/3 plans) — completed 2026-02-16
- [x] Phase 3: Core Lifecycle Integration (5/5 plans) — completed 2026-02-17
- [x] Phase 4: Role Provisioning (4/4 plans) — completed 2026-02-17
- [x] Phase 5: GUI Integration (4/4 plans) — completed 2026-02-17
- [x] Phase 6: Multi-Host Coordination (5/5 plans) — completed 2026-02-17

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v1.1 Production Robustness (Phases 7-10) - SHIPPED 2026-02-17</summary>

- [x] Phase 7: Security & Reliability Fixes (2/2 plans) — completed 2026-02-17
- [x] Phase 8: Orchestrator Extraction (4/4 plans) — completed 2026-02-17
- [x] Phase 9: Error Handling (4/4 plans) — completed 2026-02-17
- [x] Phase 10: Module Diagnostics (3/3 plans) — completed 2026-02-17

Full details: `.planning/milestones/v1.1-ROADMAP.md`

</details>

<details>
<summary>✅ v1.2 Delivery Readiness (Phases 11-13) - SHIPPED 2026-02-20</summary>

- [x] Phase 11: Documentation and Onboarding (10/10 plans) — completed 2026-02-20
- [x] Phase 12: CI/CD and Release Automation (3/3 plans) — completed 2026-02-20
- [x] Phase 13: Test Coverage Expansion (3/3 plans) — completed 2026-02-20

Full details: `.planning/milestones/v1.2-ROADMAP.md`

</details>

### v1.3 Lab Scenarios & Operator Tooling (In Progress)

- [x] **Phase 14: Lab Scenario Templates** - Pre-built scenario definitions with CLI integration and resource estimation (completed 2026-02-20)
- [x] **Phase 15: Configuration Validation** - Pre-deployment checks with guided diagnostics and resource comparison (completed 2026-02-20)
- [ ] **Phase 16: Snapshot Lifecycle** - Snapshot inventory, age-based pruning, and status integration
- [ ] **Phase 17: GUI Dashboard Enhancements** - Health banner, resource usage summary, and bulk quick-actions

## Phase Details

### Phase 14: Lab Scenario Templates
**Goal**: Operators can deploy common lab topologies from named scenario templates without manually editing configuration files
**Depends on**: Phase 13 (existing test infrastructure and CI pipeline)
**Requirements**: TMPL-01, TMPL-02, TMPL-03, TMPL-04, TMPL-05
**Success Criteria** (what must be TRUE):
  1. Operator can run a deploy command with `-Scenario SecurityLab` and get a DC + client + Linux attack VM lab created
  2. Operator can run a deploy command with `-Scenario MultiTierApp` and get a DC + SQL + IIS + client lab created
  3. Operator can run a deploy command with `-Scenario MinimalAD` and get a single DC lab with minimum resources
  4. Operator sees RAM, disk, and CPU requirements printed before any VMs are created when using a scenario template
**Plans**: 2 plans

Plans:
- [ ] 14-01-PLAN.md — Scenario template definitions, resolver, resource estimator, and tests
- [ ] 14-02-PLAN.md — CLI -Scenario parameter wiring through orchestrator and deploy flow

### Phase 15: Configuration Validation
**Goal**: Operators get clear pass/fail feedback with actionable fix guidance before deploying, preventing wasted time on doomed deployments
**Depends on**: Phase 14 (template resource requirements feed into validation checks)
**Requirements**: CONF-01, CONF-02, CONF-03
**Success Criteria** (what must be TRUE):
  1. Operator can run a validation command and see a consolidated pass/fail report covering all preflight checks
  2. Operator sees host free RAM, disk space, and logical CPUs compared against what the selected scenario requires
  3. Every failed check includes a message explaining the problem and a concrete remediation step
**Plans**: 2 plans

Plans:
- [ ] 15-01-PLAN.md — Host resource probe, validation engine, and Pester tests
- [ ] 15-02-PLAN.md — CLI validate action and pre-deploy validation wiring

### Phase 16: Snapshot Lifecycle
**Goal**: Operators can manage checkpoint accumulation across lab VMs instead of manually hunting through Hyper-V Manager
**Depends on**: Phase 14 (templates create VMs that produce snapshots; no direct code dependency)
**Requirements**: SNAP-01, SNAP-02, SNAP-03
**Success Criteria** (what must be TRUE):
  1. Operator can list all snapshots across lab VMs and see age, creation date, and parent checkpoint name for each
  2. Operator can prune snapshots older than N days (default 7) with a single command and see what was removed
  3. Lab status output includes a snapshot inventory summary (count, oldest, newest) without extra commands
**Plans**: 2 plans

Plans:
- [ ] 16-01-PLAN.md — Snapshot inventory and age-based pruning functions with Pester tests
- [ ] 16-02-PLAN.md — CLI snapshot actions and status integration with integration tests

### Phase 17: GUI Dashboard Enhancements
**Goal**: Operators see lab health and resource state at a glance on the dashboard and can perform common bulk operations without switching to CLI
**Depends on**: Phase 15, Phase 16 (health banner uses validation state; dashboard can show snapshot summary)
**Requirements**: DASH-01, DASH-02, DASH-03
**Success Criteria** (what must be TRUE):
  1. Dashboard shows a health banner indicating overall lab state (Healthy / Degraded / Offline / No Lab) that updates when the view refreshes
  2. Dashboard shows total RAM and CPU allocated across running VMs compared to host availability
  3. Operator can click Start All, Stop All, or Save Checkpoint buttons and the action applies to all lab VMs
**Plans**: TBD

Plans:
- [ ] 17-01: TBD
- [ ] 17-02: TBD

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1-6 | v1.0 | 25/25 | Complete | 2026-02-17 |
| 7-10 | v1.1 | 13/13 | Complete | 2026-02-17 |
| 11-13 | v1.2 | 16/16 | Complete | 2026-02-20 |
| 14. Lab Scenario Templates | 2/2 | Complete    | 2026-02-20 | - |
| 15. Configuration Validation | 2/2 | Complete    | 2026-02-20 | - |
| 16. Snapshot Lifecycle | v1.3 | 0/2 | Planned | - |
| 17. GUI Dashboard Enhancements | v1.3 | 0/TBD | Not started | - |

**Total: 54 plans across 13 phases, 3 milestones shipped. v1.3: 4 phases planned.**

---
*Roadmap created: 2026-02-16 (v1.0)*
*v1.1 milestone added: 2026-02-17*
*v1.2 milestone shipped: 2026-02-20*
*v1.3 milestone added: 2026-02-19*
