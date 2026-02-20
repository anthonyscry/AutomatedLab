# Roadmap: AutomatedLab

## Milestones

- ✅ **v1.0 Brownfield Hardening & Integration** - Phases 1-6 (shipped 2026-02-17)
- ✅ **v1.1 Production Robustness** - Phases 7-10 (shipped 2026-02-17)
- ✅ **v1.2 Delivery Readiness** - Phases 11-13 (shipped 2026-02-20)
- ✅ **v1.3 Lab Scenarios & Operator Tooling** - Phases 14-17 (shipped 2026-02-20)
- 🔄 **v1.4 Configuration Management & Reporting** - Phases 18-21 (active)

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

<details>
<summary>✅ v1.3 Lab Scenarios & Operator Tooling (Phases 14-17) - SHIPPED 2026-02-20</summary>

- [x] Phase 14: Lab Scenario Templates (2/2 plans) — completed 2026-02-20
- [x] Phase 15: Configuration Validation (2/2 plans) — completed 2026-02-20
- [x] Phase 16: Snapshot Lifecycle (2/2 plans) — completed 2026-02-20
- [x] Phase 17: GUI Dashboard Enhancements (2/2 plans) — completed 2026-02-20

Full details: `.planning/milestones/v1.3-ROADMAP.md`

</details>

### v1.4 Configuration Management & Reporting (Phases 18-21)

- [x] **Phase 18: Configuration Profiles** - CLI save, load, list, and delete named lab configuration profiles (completed 2026-02-20)
- [ ] **Phase 19: Run History Tracking** - Automatic deployment logging with CLI viewing and per-run detail
- [ ] **Phase 20: GUI Log Viewer** - Dedicated GUI panel with filtering and export for run history
- [ ] **Phase 21: Lab Export/Import** - Portable lab definition packages with integrity validation

## Phase Details

### Phase 18: Configuration Profiles
**Goal**: Operators can persist and reuse named lab configurations without manual file management
**Depends on**: Nothing (builds on existing Lab-Config.ps1 infrastructure)
**Requirements**: PROF-01, PROF-02, PROF-03, PROF-04
**Success Criteria** (what must be TRUE):
  1. Operator runs `Save-LabProfile -Name "dev-cluster"` and the profile appears in subsequent list commands
  2. Operator runs `Load-LabProfile -Name "dev-cluster"` and the active lab configuration reflects the saved values
  3. Operator runs `Get-LabProfile` and sees a table of all saved profiles with VM count and creation date
  4. Operator runs `Remove-LabProfile -Name "dev-cluster"` and the profile no longer appears in the list
**Plans**: 2 plans
Plans:
- [ ] 18-01-PLAN.md — Save, list, and delete profile cmdlets (Save-LabProfile, Get-LabProfile, Remove-LabProfile)
- [ ] 18-02-PLAN.md — Load profile cmdlet and comprehensive Pester tests (Load-LabProfile, LabProfile.Tests.ps1)

### Phase 19: Run History Tracking
**Goal**: Every deploy and teardown action is automatically logged so operators can review what happened and when
**Depends on**: Phase 18 (profiles provide context for logged configurations)
**Requirements**: HIST-01, HIST-02, HIST-03
**Success Criteria** (what must be TRUE):
  1. After a deploy or teardown completes, a run log entry exists with timestamp, action type, outcome, and duration
  2. Operator runs `Get-LabRunHistory` and sees a formatted table of the last N runs without manual log parsing
  3. Operator runs `Get-LabRunHistory -RunId <id>` and sees the full detail log for that specific run
**Plans**: TBD

### Phase 20: GUI Log Viewer
**Goal**: Operators can review, search, and export run history directly from the GUI without switching to a terminal
**Depends on**: Phase 19 (run history data must exist before the GUI panel can display it)
**Requirements**: LOGV-01, LOGV-02, LOGV-03
**Success Criteria** (what must be TRUE):
  1. The GUI contains a dedicated log viewer panel that displays recent run history without opening a terminal
  2. Operator selects an action type filter (deploy, teardown, snapshot) in the GUI and the log list narrows to matching entries
  3. Operator clicks Export in the GUI log viewer and a text file is saved containing the currently visible log entries
**Plans**: TBD

### Phase 21: Lab Export/Import
**Goal**: Operators can package a lab definition for transfer or backup and redeploy it on any compatible host
**Depends on**: Phase 18 (profiles are the unit of export), Phase 19 (import integrates with run logging)
**Requirements**: XFER-01, XFER-02, XFER-03
**Success Criteria** (what must be TRUE):
  1. Operator runs `Export-LabPackage -Name "dev-cluster" -Path ./export` and receives a self-contained JSON package containing the config and template
  2. Operator runs `Import-LabPackage -Path ./export/dev-cluster.json` on a different host and can deploy from it without manual file editing
  3. Import command rejects a malformed or incomplete package before any configuration is applied, displaying which fields failed validation
**Plans**: TBD

## Progress

| Phase | Milestone | Plans | Status | Completed |
|-------|-----------|-------|--------|-----------|
| 1-6 | v1.0 | 25/25 | Complete | 2026-02-17 |
| 7-10 | v1.1 | 13/13 | Complete | 2026-02-17 |
| 11-13 | v1.2 | 16/16 | Complete | 2026-02-20 |
| 14-17 | v1.3 | 8/8 | Complete | 2026-02-20 |
| 18 | 2/2 | Complete    | 2026-02-20 | - |
| 19 | v1.4 | 0/TBD | Not started | - |
| 20 | v1.4 | 0/TBD | Not started | - |
| 21 | v1.4 | 0/TBD | Not started | - |

**Total: 62 plans across 17 phases shipped. 4 active phases (18-21) in v1.4.**

---
*Roadmap created: 2026-02-16 (v1.0)*
*v1.1 milestone added: 2026-02-17*
*v1.2 milestone shipped: 2026-02-20*
*v1.3 milestone shipped: 2026-02-20*
*v1.4 milestone added: 2026-02-20*
