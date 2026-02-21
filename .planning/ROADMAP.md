# Roadmap: AutomatedLab

## Milestones

- ✅ **v1.0 Brownfield Hardening & Integration** - Phases 1-6 (shipped 2026-02-17)
- ✅ **v1.1 Production Robustness** - Phases 7-10 (shipped 2026-02-17)
- ✅ **v1.2 Delivery Readiness** - Phases 11-13 (shipped 2026-02-20)
- ✅ **v1.3 Lab Scenarios & Operator Tooling** - Phases 14-17 (shipped 2026-02-20)
- ✅ **v1.4 Configuration Management & Reporting** - Phases 18-21 (shipped 2026-02-20)
- 🔄 **v1.5 Advanced Scenarios & Multi-OS** - Phases 22-25

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

<details>
<summary>✅ v1.4 Configuration Management & Reporting (Phases 18-21) - SHIPPED 2026-02-20</summary>

- [x] Phase 18: Configuration Profiles (2/2 plans) — completed 2026-02-20
- [x] Phase 19: Run History Tracking (2/2 plans) — completed 2026-02-20
- [x] Phase 20: GUI Log Viewer (2/2 plans) — completed 2026-02-20
- [x] Phase 21: Lab Export/Import (2/2 plans) — completed 2026-02-20

Full details: `.planning/milestones/v1.4-ROADMAP.md`

</details>

### v1.5 Advanced Scenarios & Multi-OS (Phases 22-25)

**Goal:** Custom role templates, complex networking topologies, and full Linux VM parity for advanced lab scenarios.

#### Phase 22: Custom Role Templates
**Goal:** Operator-defined roles as JSON files that auto-discover and integrate with existing workflows.
**Requirements:** ROLE-01, ROLE-02, ROLE-03, ROLE-04, ROLE-05
**Dependencies:** None (builds on existing LabBuilder/Roles/ pattern)

**Success criteria:**
- JSON role definitions in `.planning/roles/` auto-discovered at runtime
- Custom roles appear in Select-LabRoles UI and CLI
- Validation rejects malformed role templates with clear error messages
- `Get-LabCustomRole -List` shows available custom roles with metadata

**Plans:** 2/2 plans complete

Plans:
- [ ] 22-01-PLAN.md — Custom role engine: JSON schema, validator, auto-discovery, listing
- [ ] 22-02-PLAN.md — Integration with Select-LabRoles, Invoke-LabBuilder, Build-LabFromSelection

---

#### Phase 23: Complex Networking
**Goal:** Multi-switch, multi-subnet lab topologies with VLAN support.
**Requirements:** NET-01, NET-02, NET-03, NET-04, NET-05
**Dependencies:** None (extends existing New-LabSwitch/New-LabNAT)

**Success criteria:**
- Lab config supports named switches array (not just single SwitchName)
- VMs reference switches by name in their config
- Inter-subnet routing configurable (gateway VM or host routing)
- VLAN IDs assignable per VM adapter
- Pre-deployment validation catches subnet overlap across switches

**Plans:** 2/2 plans complete

Plans:
- [ ] 23-01-PLAN.md — Multi-switch config schema, creation, and subnet conflict validation
- [ ] 23-02-PLAN.md — VM-to-switch assignment, VLAN tagging, and inter-subnet routing

---

#### Phase 24: Linux VM Parity
**Goal:** Full lifecycle parity for Linux VMs including CentOS support.
**Requirements:** LNX-01, LNX-02, LNX-03, LNX-04, LNX-06
**Dependencies:** None (extends existing LinuxRoleBase.ps1)

**Success criteria:**
- Linux VMs support snapshot create/restore/prune same as Windows
- Linux VM settings preserved in configuration profiles
- CentOS/RHEL provisioning via cloud-init or kickstart
- SSH role application has configurable retry count and timeout
- All existing Linux roles work on both Ubuntu and CentOS

**Plans:** 2/2 plans complete

Plans:
- [ ] 24-01-PLAN.md — Linux VM snapshot/profile parity (inventory, pruning, profile round-trip)
- [ ] 24-02-PLAN.md — SSH retry with configurable count and CentOS role support

---

#### Phase 25: Mixed OS Integration
**Goal:** End-to-end mixed OS scenarios validated and scenario templates updated.
**Requirements:** LNX-05
**Dependencies:** Phase 22 (custom roles), Phase 23 (networking), Phase 24 (Linux parity)

**Success criteria:**
- Mixed Windows/Linux scenario template works end-to-end (DC + Linux app servers)
- Scenario templates updated to leverage multi-switch and custom role capabilities
- Integration tests cover cross-OS provisioning, networking, and teardown
- Documentation updated for mixed OS lab workflows

**Plans:** TBD (created during `/gsd:plan-phase 25`)

## Progress

| Milestone | Phases | Plans | Status | Shipped |
|-----------|--------|-------|--------|---------|
| v1.0 | 1-6 | 25 | Complete | 2026-02-17 |
| v1.1 | 7-10 | 13 | Complete | 2026-02-17 |
| v1.2 | 11-13 | 16 | Complete | 2026-02-20 |
| v1.3 | 14-17 | 8 | Complete | 2026-02-20 |
| v1.4 | 18-21 | 8 | Complete | 2026-02-20 |
| v1.5 | 22-25 | TBD | In Progress | — |

**Total: 70 plans across 21 phases shipped + v1.5 in progress.**

---
*Roadmap created: 2026-02-16 (v1.0)*
*v1.1 milestone added: 2026-02-17*
*v1.2 milestone shipped: 2026-02-20*
*v1.3 milestone shipped: 2026-02-20*
*v1.4 milestone shipped: 2026-02-20*
*v1.5 milestone added: 2026-02-20*
