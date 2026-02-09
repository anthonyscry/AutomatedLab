# Requirements: SimpleLab

**Defined:** 2025-02-09
**Core Value:** One command builds a Windows domain lab; one command tears it down.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Lab Build

- [ ] **BUILD-01**: User can build Windows domain lab with one command
- [ ] **BUILD-02**: Tool creates Active Directory domain controller with DNS
- [ ] **BUILD-03**: Tool validates Windows ISOs exist before attempting build
- [ ] **BUILD-04**: Tool provisions VMs (DC, Server 2019, Win 11) quickly

### VM Lifecycle

- [ ] **LIFE-01**: User can start all lab VMs with one command
- [ ] **LIFE-02**: User can stop all lab VMs with one command
- [ ] **LIFE-03**: User can restart individual VMs
- [ ] **LIFE-04**: Tool displays status of all VMs (running, stopped, off)
- [ ] **LIFE-05**: User can remove lab VMs while preserving templates/ISOs
- [ ] **LIFE-06**: User can run clean slate command to remove everything (VMs, checkpoints, switches)
- [ ] **LIFE-07**: User can create snapshot of lab at known-good state
- [ ] **LIFE-08**: User can rollback lab to previous snapshot

### Networking

- [ ] **NET-01**: Tool creates dedicated Internal vSwitch for lab VMs
- [ ] **NET-02**: Tool configures IP addresses for all VMs
- [ ] **NET-03**: User can start all lab VMs with one command

### User Experience

- [ ] **UX-01**: Tool displays clear error messages when operations fail
- [ ] **UX-02**: Tool presents interactive menu for selecting operations
- [ ] **UX-03**: Tool generates JSON report after each operation (run artifacts)
- [ ] **UX-04**: Tool supports non-interactive mode with command-line flags

### Validation

- [ ] **VAL-01**: Tool verifies Hyper-V is enabled on local machine before operations
- [ ] **VAL-02**: Tool verifies required Windows ISOs are present before build

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Features

- **BUILD-10**: Health gate validation with automatic rollback on failed deployments
- **LIFE-10**: Core-only mode (skip Linux VMs for faster builds)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Linux VM support | Was main source of complexity; different automation model |
| Azure integration | Different platform, doubles surface area |
| Multi-domain forests | Most users don't need this; adds config burden |
| GUI/Windows Forms | Maintenance burden; PowerShell-native is better |
| Custom role system | Most users never use it; adds documentation burden |
| SQL Server role | Heavy resource use; slow install; niche need |
| Cluster support | Over-engineering for lab scenarios |
| Complex network topologies | Most users want simple VLANs |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUILD-01 | Phase 4 | Pending |
| BUILD-02 | Phase 5 | Pending |
| BUILD-03 | Phase 2 | Pending |
| BUILD-04 | Phase 4 | Pending |
| LIFE-01 | Phase 6 | Pending |
| LIFE-02 | Phase 6 | Pending |
| LIFE-03 | Phase 6 | Pending |
| LIFE-04 | Phase 6 | Pending |
| LIFE-05 | Phase 7 | Pending |
| LIFE-06 | Phase 7 | Pending |
| LIFE-07 | Phase 8 | Pending |
| LIFE-08 | Phase 8 | Pending |
| NET-01 | Phase 3 | Pending |
| NET-02 | Phase 3 | Pending |
| NET-03 | Phase 6 | Pending |
| UX-01 | Phase 1 | Pending |
| UX-02 | Phase 9 | Pending |
| UX-03 | Phase 1 | Pending |
| UX-04 | Phase 9 | Pending |
| VAL-01 | Phase 1 | Pending |
| VAL-02 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0 ✓

**Note:** NET-03 is functionally equivalent to LIFE-01 (start all lab VMs) and is mapped to Phase 6 for implementation purposes.

---
*Requirements defined: 2025-02-09*
*Last updated: 2026-02-09 after roadmap creation*
