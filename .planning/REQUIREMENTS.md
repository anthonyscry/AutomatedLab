# Requirements: AutomatedLab v1.5 Advanced Scenarios & Multi-OS

**Defined:** 2026-02-20
**Core Value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.

## v1 Requirements

Requirements for advanced scenarios and multi-OS milestone. Each maps to roadmap phases.

### Custom Role Templates

- [x] **ROLE-01**: Operator can define custom roles as JSON files with provisioning steps mapped to existing primitives
- [x] **ROLE-02**: System auto-discovers custom role templates at runtime (file drop, no code changes)
- [x] **ROLE-03**: Custom roles integrate with existing role selection UI and CLI workflows
- [x] **ROLE-04**: Custom role templates validate on load (required fields, valid provisioning steps)
- [x] **ROLE-05**: Operator can list available custom roles with description and resource requirements

### Complex Networking

- [x] **NET-01**: Operator can configure multiple vSwitches in a single lab (named switches with distinct subnets)
- [x] **NET-02**: VMs can be assigned to specific vSwitches by name in lab configuration
- [x] **NET-03**: System supports multi-subnet labs with routing between subnets
- [x] **NET-04**: Operator can configure VLAN tagging on VM network adapters
- [x] **NET-05**: Pre-deployment validation checks for subnet conflicts across multiple switches

### Linux VM Full Parity

- [x] **LNX-01**: Linux VMs support full provisioning lifecycle (create, start, stop, snapshot, teardown) matching Windows VMs
- [x] **LNX-02**: SSH-based role application works for all existing Linux roles with retry and timeout handling
- [x] **LNX-03**: Linux VMs integrate with snapshot management (inventory, pruning, restore)
- [x] **LNX-04**: Linux VMs integrate with configuration profiles (save/load preserves Linux VM settings)
- [x] **LNX-05**: Mixed OS scenarios work end-to-end (Windows DC + Linux app servers in same lab)
- [x] **LNX-06**: CentOS/RHEL support added alongside existing Ubuntu (cloud-init or kickstart provisioning)

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Advanced Role System

- **AROLE-01**: Role dependency resolution (e.g., SQL role requires DC role to be deployed first)
- **AROLE-02**: Role parameter validation against live environment state

### Advanced Networking

- **ANET-01**: DMZ network patterns with firewall rules between segments
- **ANET-02**: Network topology visualization in GUI dashboard

### Advanced Multi-OS

- **AOS-01**: Fedora/Debian distribution support
- **AOS-02**: Linux-to-Windows domain join automation

## Out of Scope

| Feature | Reason |
|---------|--------|
| Azure/cloud backend support | Hyper-V local only — out of product direction |
| Multi-domain forest scenarios | Niche, document manual approach |
| Custom scenario builder GUI wizard | CLI + JSON templates sufficient |
| Real-time network traffic monitoring | Out of scope for lab provisioning tool |
| Container-native networking (CNI) | Hyper-V vSwitch networking only |
| BSD/macOS VM support | Hyper-V Linux integration services scope |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ROLE-01 | Phase 22 | Complete |
| ROLE-02 | Phase 22 | Complete |
| ROLE-03 | Phase 22 | Complete |
| ROLE-04 | Phase 22 | Complete |
| ROLE-05 | Phase 22 | Complete |
| NET-01 | Phase 23 | Complete |
| NET-02 | Phase 23 | Complete |
| NET-03 | Phase 23 | Complete |
| NET-04 | Phase 23 | Complete |
| NET-05 | Phase 23 | Complete |
| LNX-01 | Phase 24 | Complete |
| LNX-02 | Phase 24 | Complete |
| LNX-03 | Phase 24 | Complete |
| LNX-04 | Phase 24 | Complete |
| LNX-05 | Phase 25 | Complete |
| LNX-06 | Phase 24 | Complete |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap creation (all 16 requirements mapped)*
