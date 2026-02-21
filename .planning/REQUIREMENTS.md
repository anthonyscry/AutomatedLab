# Requirements: AutomatedLab

**Defined:** 2026-02-20
**Core Value:** Every function handles errors explicitly, surfaces clear diagnostics, and stays modular enough that each piece can be tested and maintained independently.

## v1.6 Requirements

Requirements for Lab Lifecycle & Security Automation milestone. Each maps to roadmap phases.

### Lab Lifecycle

- [ ] **TTL-01**: Operator can configure lab TTL duration in Lab-Config.ps1 (hours, with safe defaults)
- [ ] **TTL-02**: Background scheduled task auto-suspends all lab VMs when TTL expires
- [ ] **TTL-03**: Lab uptime is tracked and queryable via Get-LabUptime cmdlet

### Security Baselines (PowerSTIG)

- [x] **STIG-01**: PowerSTIG and required DSC dependencies auto-install on target VMs during PostInstall
- [x] **STIG-02**: Role-appropriate STIG MOFs compile and apply via DSC push mode at deploy time
- [ ] **STIG-03**: Compliance status cached to JSON file after each STIG application
- [x] **STIG-04**: Per-VM STIG exception overrides configurable in Lab-Config.ps1 STIG block
- [ ] **STIG-05**: Operator can re-apply STIG baselines on demand via Invoke-LabSTIGBaseline
- [ ] **STIG-06**: Compliance report generated via Get-LabSTIGCompliance with per-VM breakdown

### ADMX / GPO Management

- [ ] **GPO-01**: ADMX central store auto-populated on DC after domain promotion completes
- [ ] **GPO-02**: Baseline GPO created and linked to domain from JSON template definitions
- [ ] **GPO-03**: Pre-built security GPO templates shipped (password policy, account lockout, audit policy, AppLocker)
- [ ] **GPO-04**: Third-party ADMX bundles importable via config setting with download + copy workflow

### Dashboard Enrichment

- [ ] **DASH-01**: Per-VM snapshot age displayed on dashboard with configurable staleness warnings
- [ ] **DASH-02**: VHDx disk usage shown per VM with disk pressure indicators
- [ ] **DASH-03**: VM uptime displayed with configurable stale threshold alerts
- [ ] **DASH-04**: STIG compliance status column reads from cached compliance JSON data
- [ ] **DASH-05**: Background runspace collects enriched VM data without freezing UI thread

## Future Requirements

Deferred to future releases. Tracked but not in current roadmap.

### Lab Lifecycle (v2)

- **TTL-V2-01**: Operator snooze/extend TTL from CLI or GUI
- **TTL-V2-02**: Grace period notification before auto-suspend
- **TTL-V2-03**: Per-lab TTL override for multi-lab scenarios

### Health Checks (v2)

- **HLTH-01**: Role-level application health checks (HTTP, SQL port, service status)
- **HLTH-02**: Application endpoint reachability testing post-deployment

### Multi-Lab (v2)

- **MLAB-01**: Namespace isolation for concurrent lab instances on one host

## Out of Scope

| Feature | Reason |
|---------|--------|
| DSC pull server for STIG remediation | Overkill for single-host lab; push mode sufficient |
| Continuous DSC compliance remediation | Fights running workloads; one-time apply + re-apply on demand |
| TTL-based auto-teardown (destroy) | Irreversible; suspend-only protects operator work |
| Live DSC compliance polling in dashboard | Too slow; cache-on-write pattern instead |
| Third-party ADMX auto-download from internet | Security concern; operator provides bundles, tool imports them |
| Network topology visualization in GUI | Text-based config sufficient per v1.5 decision |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TTL-01 | Phase 26 | Pending |
| TTL-02 | Phase 26 | Pending |
| TTL-03 | Phase 26 | Pending |
| STIG-01 | Phase 27 | Complete |
| STIG-02 | Phase 27 | Complete |
| STIG-03 | Phase 27 | Pending |
| STIG-04 | Phase 27 | Complete |
| STIG-05 | Phase 27 | Pending |
| STIG-06 | Phase 27 | Pending |
| GPO-01 | Phase 28 | Pending |
| GPO-02 | Phase 28 | Pending |
| GPO-03 | Phase 28 | Pending |
| GPO-04 | Phase 28 | Pending |
| DASH-01 | Phase 29 | Pending |
| DASH-02 | Phase 29 | Pending |
| DASH-03 | Phase 29 | Pending |
| DASH-04 | Phase 29 | Pending |
| DASH-05 | Phase 29 | Pending |

**Coverage:**
- v1.6 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap creation (18/18 mapped)*
