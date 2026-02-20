# Requirements: AutomatedLab v1.3 Lab Scenarios & Operator Tooling

**Defined:** 2026-02-19
**Core Value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.

## v1 Requirements

Requirements for lab scenarios and operator tooling milestone. Each maps to roadmap phases.

### Lab Scenario Templates

- [ ] **TMPL-01**: Operator can deploy a security testing lab template (DC + client + Linux attack VM) via single scenario selection
- [ ] **TMPL-02**: Operator can deploy a multi-tier application lab template (DC + SQL + IIS web server + client) via single scenario selection
- [ ] **TMPL-03**: Operator can deploy a minimal AD lab template (DC only, minimum resources) for quick testing
- [ ] **TMPL-04**: Operator can select a scenario template via CLI `-Scenario` parameter on deploy action
- [ ] **TMPL-05**: Operator sees resource requirements (RAM, disk, CPU) before deploying a scenario template

### Configuration Validation

- [ ] **CONF-01**: Operator runs a pre-deployment validation report that combines all preflight checks with clear pass/fail summary
- [ ] **CONF-02**: Operator sees host resource availability (free RAM, disk space, logical CPUs) compared against template requirements before deployment
- [ ] **CONF-03**: Each failed validation includes a guided diagnostic message explaining what is wrong and how to fix it

### Snapshot Lifecycle

- [ ] **SNAP-01**: Operator can list all snapshots with age, creation date, and parent checkpoint name across all lab VMs
- [ ] **SNAP-02**: Operator can prune stale snapshots older than a configurable threshold (default 7 days)
- [ ] **SNAP-03**: Operator sees snapshot inventory summary when running lab status command

### GUI Dashboard

- [ ] **DASH-01**: Dashboard displays a health summary banner showing overall lab state (Healthy / Degraded / Offline / No Lab)
- [ ] **DASH-02**: Dashboard displays resource usage summary (total RAM/CPU allocated across VMs vs host available)
- [ ] **DASH-03**: Dashboard includes quick-action buttons (Start All, Stop All, Save Checkpoint) for common bulk operations

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Advanced Scenarios

- **ASCN-01**: Custom scenario builder wizard in GUI (deferred — CLI + JSON templates sufficient for v1.3)
- **ASCN-02**: Scenario template sharing/import from external sources (deferred — local templates only)

### Advanced Snapshot Management

- **ASNP-01**: Snapshot diff/comparison between two points in time (deferred — prune and list sufficient)
- **ASNP-02**: Snapshot size tracking and disk usage reporting (deferred — Hyper-V API complexity)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Azure/cloud backend support | Hyper-V local only — out of product direction |
| Multi-domain forest templates | Niche requirement, document manual approach |
| Custom role plugin system | Validate core scenario templates first |
| Linux VM behavior expansion | Maintain compatibility only |
| Template marketplace/sharing | Premature for single-developer project |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TMPL-01 | Phase 14 | Pending |
| TMPL-02 | Phase 14 | Pending |
| TMPL-03 | Phase 14 | Pending |
| TMPL-04 | Phase 14 | Pending |
| TMPL-05 | Phase 14 | Pending |
| CONF-01 | Phase 15 | Pending |
| CONF-02 | Phase 15 | Pending |
| CONF-03 | Phase 15 | Pending |
| SNAP-01 | Phase 16 | Pending |
| SNAP-02 | Phase 16 | Pending |
| SNAP-03 | Phase 16 | Pending |
| DASH-01 | Phase 17 | Pending |
| DASH-02 | Phase 17 | Pending |
| DASH-03 | Phase 17 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-02-19*
*Last updated: 2026-02-19 after roadmap creation*
