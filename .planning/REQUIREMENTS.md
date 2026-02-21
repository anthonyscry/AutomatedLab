# Requirements: AutomatedLab

**Defined:** 2026-02-21
**Core Value:** Every function handles errors explicitly, surfaces clear diagnostics, and stays modular enough that each piece can be tested and maintained independently.

## v1.7 Requirements

Requirements for Operational Excellence & Analytics milestone. Each maps to roadmap phases.

### Lab Analytics

- [ ] **ANLY-01**: Operator can view lab usage trends over time (VM uptime, resource consumption patterns)
- [ ] **ANLY-02**: Operator can export lab usage data to CSV/JSON for external analysis
- [ ] **ANLY-03**: System automatically tracks lab creation, deployment, and teardown events in analytics log

### Advanced Reporting

- [ ] **RPT-01**: Operator can generate compliance reports (STIG status across all VMs, pass/fail summary)
- [ ] **RPT-02**: Operator can generate resource utilization reports (disk, memory, CPU trends)
- [ ] **RPT-03**: Operator can schedule automated report generation (daily/weekly compliance snapshots)
- [ ] **RPT-04**: Reports include timestamp, lab name, and summary statistics for audit trail

### Operational Workflows

- [x] **OPS-01**: Operator can perform bulk VM operations (start/stop/suspend multiple VMs at once)
- [ ] **OPS-02**: Operator can create custom operation workflows (scripts that combine common actions)
- [ ] **OPS-03**: System validates bulk operations before execution (pre-flight checks, resource availability)
- [ ] **OPS-04**: Operator receives confirmation summary after bulk operations complete

### Performance Guidance

- [ ] **PERF-01**: Operator can view performance metrics for VM operations (provision time, snapshot duration)
- [ ] **PERF-02**: System provides optimization suggestions when performance degrades detected
- [ ] **PERF-03**: Performance data is collected automatically and stored for historical analysis

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Cloud Integration

- **CLOUD-01**: Azure lab provisioning support
- **CLOUD-02**: Hybrid Hyper-V/Azure scenarios
- **CLOUD-03**: Cloud-based image library

### Advanced Networking

- **NETX-01**: Software-defined networking overlay
- **NETX-02**: Network simulation tools (packet loss, latency injection)
- **NETX-03**: Advanced firewall rule management

### Multi-Forest Domains

- **FOREST-01**: Multi-domain forest provisioning
- **FOREST-02**: Cross-forest trust automation
- **FOREST-03**: Federated authentication scenarios

## Out of Scope

| Feature | Reason |
|---------|--------|
| Real-time alerting (email/SMS) | Use external monitoring tools |
| Predictive analytics/AI recommendations | Beyond current scope, data science effort |
| Custom GUI report builder | CLI + export sufficient for v1.7 |
| Database-backed analytics storage | File-based storage simpler, sufficient |
| Distributed lab coordination across hosts | Multi-host already exists, scale-out deferred |
| Dynamic resource scaling (hot-add RAM/CPU) | Hyper-V limitation, document manual approach |
| Network traffic capture/analysis | Use external tools (Wireshark, NetMon) |
| Automated remediation workflows | Manual approval preferred for production labs |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ANLY-01 | Phase 30 | Pending |
| ANLY-02 | Phase 30 | Pending |
| ANLY-03 | Phase 30 | Pending |
| RPT-01 | Phase 31 | Pending |
| RPT-02 | Phase 31 | Pending |
| RPT-03 | Phase 31 | Pending |
| RPT-04 | Phase 31 | Pending |
| OPS-01 | Phase 32 | Complete |
| OPS-02 | Phase 32 | Pending |
| OPS-03 | Phase 32 | Pending |
| OPS-04 | Phase 32 | Pending |
| PERF-01 | Phase 33 | Pending |
| PERF-02 | Phase 33 | Pending |
| PERF-03 | Phase 33 | Pending |

**Coverage:**
- v1.7 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-02-21 after initial definition*
