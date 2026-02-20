# Requirements: AutomatedLab v1.4 Configuration Management & Reporting

**Defined:** 2026-02-20
**Core Value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.

## v1 Requirements

Requirements for configuration management and reporting milestone. Each maps to roadmap phases.

### Configuration Profiles

- [ ] **PROF-01**: Operator can save current lab configuration as a named profile
- [ ] **PROF-02**: Operator can load a saved profile to restore lab configuration
- [ ] **PROF-03**: Operator can list all saved profiles with summary info (VM count, creation date)
- [ ] **PROF-04**: Operator can delete a saved profile by name

### Run History

- [ ] **HIST-01**: System automatically logs each deploy/teardown action with timestamp, outcome, and duration
- [ ] **HIST-02**: Operator can view run history as a formatted table (last N runs)
- [ ] **HIST-03**: Operator can view detailed log for a specific run by ID

### GUI Log Viewer

- [ ] **LOGV-01**: GUI includes a dedicated log viewer panel showing recent run history
- [ ] **LOGV-02**: Operator can filter log entries by action type (deploy, teardown, snapshot) in the GUI
- [ ] **LOGV-03**: Operator can export visible log entries to a text file from the GUI

### Lab Export/Import

- [ ] **XFER-01**: Operator can export a lab configuration (config + template) as a portable JSON package
- [ ] **XFER-02**: Operator can import a lab configuration package and deploy from it
- [ ] **XFER-03**: Import validates package integrity before applying (schema check, required fields)

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Advanced Profiles

- **APROF-01**: Operator can diff two profiles to see configuration differences
- **APROF-02**: Operator can merge settings from one profile into another

### Advanced Reporting

- **ARPT-01**: Dashboard shows deployment success rate trend over time
- **ARPT-02**: System generates weekly summary email of lab activity

## Out of Scope

| Feature | Reason |
|---------|--------|
| Azure/cloud backend support | Hyper-V local only — out of product direction |
| Cloud-based profile sync | Local-only project, no cloud infrastructure |
| Real-time log streaming | Run logs are captured post-action, not streamed |
| Custom log retention policies | Simple file-based logging sufficient for operator needs |
| Multi-user profile sharing | Single-developer/operator project |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROF-01 | Phase 18 | Pending |
| PROF-02 | Phase 18 | Pending |
| PROF-03 | Phase 18 | Pending |
| PROF-04 | Phase 18 | Pending |
| HIST-01 | Phase 19 | Pending |
| HIST-02 | Phase 19 | Pending |
| HIST-03 | Phase 19 | Pending |
| LOGV-01 | Phase 20 | Pending |
| LOGV-02 | Phase 20 | Pending |
| LOGV-03 | Phase 20 | Pending |
| XFER-01 | Phase 21 | Pending |
| XFER-02 | Phase 21 | Pending |
| XFER-03 | Phase 21 | Pending |

**Coverage:**
- v1 requirements: 13 total
- Mapped to phases: 13
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap creation (all 13 requirements mapped)*
