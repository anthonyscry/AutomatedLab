# Roadmap: SimpleLab

## Overview

SimpleLab delivers a streamlined Windows domain lab experience through foundational infrastructure, validation, provisioning, domain configuration, lifecycle management, and user experience layers. Starting with project scaffolding and pre-flight checks, the roadmap progresses through network setup, VM provisioning, and domain creation before adding resilience features like snapshots and rollback, culminating in a polished menu-driven interface that makes lab automation accessible to non-PowerShell experts.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Project Foundation** - Infrastructure scaffolding and error handling
- [ ] **Phase 2: Pre-flight Validation** - ISO and prerequisite verification
- [ ] **Phase 3: Network Infrastructure** - vSwitch and IP configuration
- [ ] **Phase 4: VM Provisioning** - Hyper-V VM creation and setup
- [ ] **Phase 5: Domain Configuration** - Active Directory deployment
- [ ] **Phase 6: Lifecycle Operations** - Start, stop, restart, and status
- [ ] **Phase 7: Teardown Operations** - VM removal and clean slate
- [ ] **Phase 8: Snapshot Management** - Checkpoint creation and rollback
- [ ] **Phase 9: User Experience** - Menu interface and CLI flags

## Phase Details

### Phase 1: Project Foundation
**Goal**: Establish project infrastructure with structured error handling and run artifact generation
**Depends on**: Nothing (first phase)
**Requirements**: VAL-01, UX-01, UX-03
**Success Criteria** (what must be TRUE):
  1. User receives clear error message when Hyper-V is not enabled on their machine
  2. Tool generates JSON report after each operation containing operation type, timestamp, and status
  3. All operations use structured error handling that prevents silent failures
**Plans**: TBD

Plans:
- [ ] 01-01: Project scaffolding and directory structure
- [ ] 01-02: Hyper-V detection and validation
- [ ] 01-03: Structured error handling framework
- [ ] 01-04: Run artifact generation (JSON reports)

### Phase 2: Pre-flight Validation
**Goal**: Verify all prerequisites and ISOs exist before attempting lab operations
**Depends on**: Phase 1
**Requirements**: BUILD-03, VAL-02
**Success Criteria** (what must be TRUE):
  1. User receives specific error message listing missing ISOs before build attempt
  2. Tool validates Windows Server 2019 and Windows 11 ISOs exist in configured location
  3. User sees clear pass/fail status for all pre-flight checks
**Plans**: TBD

Plans:
- [ ] 02-01: ISO detection and validation logic
- [ ] 02-02: Pre-flight check orchestration
- [ ] 02-03: Validation error reporting UX

### Phase 3: Network Infrastructure
**Goal**: Create dedicated virtual switch with IP configuration for lab VMs
**Depends on**: Phase 1
**Requirements**: NET-01, NET-02
**Success Criteria** (what must be TRUE):
  1. Tool creates dedicated Internal vSwitch named "SimpleLab" that persists across lab rebuilds
  2. VMs receive static IP assignments on lab network (DC: 10.0.0.1, Server: 10.0.0.2, Win11: 10.0.0.3)
  3. Lab VMs can communicate with each other after network setup completes
**Plans**: TBD

Plans:
- [ ] 03-01: Internal vSwitch creation
- [ ] 03-02: IP configuration and assignment
- [ ] 03-03: Network connectivity validation

### Phase 4: VM Provisioning
**Goal**: Provision Hyper-V VMs with appropriate hardware configuration
**Depends on**: Phase 2, Phase 3
**Requirements**: BUILD-01, BUILD-04
**Success Criteria** (what must be TRUE):
  1. User can run single command to build complete Windows domain lab (DC, Server 2019, Win 11)
  2. Tool creates 3 VMs with appropriate RAM and disk allocation (DC: 2GB RAM, Server: 2GB, Win11: 4GB)
  3. VMs are created with attached ISOs and bootable configuration
  4. Provisioning completes in under 15 minutes for basic VM setup
**Plans**: TBD

Plans:
- [ ] 04-01: VM hardware configuration
- [ ] 04-02: ISO attachment and boot setup
- [ ] 04-03: One-command build orchestration
- [ ] 04-04: Provisioning performance optimization

### Phase 5: Domain Configuration
**Goal**: Deploy Active Directory domain controller with DNS and join member servers
**Depends on**: Phase 4
**Requirements**: BUILD-02
**Success Criteria** (what must be TRUE):
  1. DC promotes to domain controller with "simplelab.local" domain
  2. DNS service is running and resolving on domain controller
  3. Member servers (Server 2019, Win 11) are joined to the domain
  4. Domain is functional after single build command completes
**Plans**: TBD

Plans:
- [ ] 05-01: DC promotion automation
- [ ] 05-02: DNS configuration
- [ ] 05-03: Domain join automation
- [ ] 05-04: Domain health validation

### Phase 6: Lifecycle Operations
**Goal**: Enable start, stop, restart, and status operations for lab VMs
**Depends on**: Phase 4
**Requirements**: LIFE-01, LIFE-02, LIFE-03, LIFE-04, NET-03
**Success Criteria** (what must be TRUE):
  1. User can start all lab VMs with single command
  2. User can stop all lab VMs with single command
  3. User can restart individual VMs by name
  4. User sees status table showing running/stopped/off state for all VMs
**Plans**: TBD

Plans:
- [ ] 06-01: Start all VMs command
- [ ] 06-02: Stop all VMs command
- [ ] 06-03: Individual VM restart
- [ ] 06-04: VM status reporting

### Phase 7: Teardown Operations
**Goal**: Provide commands for VM removal and clean slate reset
**Depends on**: Phase 4
**Requirements**: LIFE-05, LIFE-06
**Success Criteria** (what must be TRUE):
  1. User can remove lab VMs while preserving ISOs and templates
  2. User can run clean slate command to remove VMs, checkpoints, and vSwitch
  3. User is prompted for confirmation before destructive operations
  4. Teardown completes without leaving orphaned Hyper-V artifacts
**Plans**: TBD

Plans:
- [ ] 07-01: VM removal command (preserves templates)
- [ ] 07-02: Clean slate command (removes everything)
- [ ] 07-03: Teardown confirmation UX
- [ ] 07-04: Artifact cleanup validation

### Phase 8: Snapshot Management
**Goal**: Enable lab snapshots for quick rollback to known-good states
**Depends on**: Phase 5
**Requirements**: LIFE-07, LIFE-08
**Success Criteria** (what must be TRUE):
  1. User can create snapshot of lab at "LabReady" state after domain configuration
  2. User can rollback lab to previous snapshot with single command
  3. Rollback completes in under 2 minutes
  4. User sees list of available snapshots before rollback selection
**Plans**: TBD

Plans:
- [ ] 08-01: Checkpoint creation
- [ ] 08-02: Snapshot listing and selection
- [ ] 08-03: Rollback execution
- [ ] 08-04: LabReady checkpoint automation

### Phase 9: User Experience
**Goal**: Deliver menu-driven interface and non-interactive CLI mode
**Depends on**: Phase 6, Phase 7, Phase 8
**Requirements**: UX-02, UX-04
**Success Criteria** (what must be TRUE):
  1. User sees interactive menu with numbered options for all operations (build, start, stop, status, snapshot, rollback, teardown)
  2. User can run tool non-interactively with CLI flags (e.g., --build, --stop, --status)
  3. Menu displays current lab status at top (VMs running/stopped)
  4. Non-interactive mode returns appropriate exit codes for automation
**Plans**: TBD

Plans:
- [ ] 09-01: Interactive menu system
- [ ] 09-02: CLI argument parsing
- [ ] 09-03: Status display integration
- [ ] 09-04: Exit code handling for automation

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Project Foundation | 0/4 | Not started | - |
| 2. Pre-flight Validation | 0/3 | Not started | - |
| 3. Network Infrastructure | 0/3 | Not started | - |
| 4. VM Provisioning | 0/4 | Not started | - |
| 5. Domain Configuration | 0/4 | Not started | - |
| 6. Lifecycle Operations | 0/4 | Not started | - |
| 7. Teardown Operations | 0/4 | Not started | - |
| 8. Snapshot Management | 0/4 | Not started | - |
| 9. User Experience | 0/4 | Not started | - |
