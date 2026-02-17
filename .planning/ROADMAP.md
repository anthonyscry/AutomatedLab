# Roadmap: AutomatedLab Hardening & Integration

## Overview

This brownfield hardening milestone transforms a 107-function PowerShell lab automation codebase from "mostly working" to "reliably works end-to-end." We clean technical debt first (archive cleanup, config unification, security hardening), then systematically integrate-test and fix core lifecycle flows (bootstrap, deploy, teardown), role provisioning, GUI operations, and multi-host coordination. Every phase completes when observable user behaviors work without errors.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Cleanup & Config Foundation** - Remove dead code, unify config system, standardize helper sourcing (2026-02-16)
- [x] **Phase 2: Security Hardening** - Eliminate hardcoded passwords, validate checksums, secure SSH operations (2026-02-16)
- [x] **Phase 3: Core Lifecycle Integration** - Bootstrap → Deploy → Teardown works end-to-end with error handling (2026-02-17)
- [ ] **Phase 4: Role Provisioning** - All 11 Windows/Linux roles provision correctly with error handling
- [ ] **Phase 5: GUI Integration** - Dashboard, Actions, Customize, Settings, Logs work with CLI feature parity
- [ ] **Phase 6: Multi-Host Coordination** - Dispatcher routes operations to remote hosts with scoped tokens

## Phase Details

### Phase 1: Cleanup & Config Foundation
**Goal**: Codebase is clean, config system unified, helper sourcing consistent — foundation ready for integration testing
**Depends on**: Nothing (first phase)
**Requirements**: CLN-01, CLN-02, CLN-03, CLN-04, CLN-05, CFG-01, CFG-02, CFG-03, CFG-04
**Success Criteria** (what must be TRUE):
  1. Archive directory removed from main branch (preserved in git history)
  2. Coverage artifacts and LSP tools removed from tracked files
  3. GlobalLabConfig is single source of truth with validation on load
  4. All entry points use consistent helper sourcing pattern (standardized)
  5. Template system reads/writes JSON with schema validation
**Plans**: 4 plans

Plans:
- [ ] 01-01-PLAN.md -- Delete .archive/, untrack artifacts, remove dead code
- [ ] 01-02-PLAN.md -- Standardize helper sourcing with fail-fast error handling
- [ ] 01-03-PLAN.md -- Unify config to $GlobalLabConfig, add validation, remove legacy vars
- [ ] 01-04-PLAN.md -- Template JSON validation on read and write

### Phase 2: Security Hardening
**Goal**: Lab deployments use secure defaults with no hardcoded credentials or insecure downloads
**Depends on**: Phase 1
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04
**Success Criteria** (what must be TRUE):
  1. Default passwords removed from config — deployment fails if password not provided via environment variable or parameter
  2. SSH operations use accept-new or known_hosts — never StrictHostKeyChecking=no
  3. All external downloads validate SHA256 checksums before execution
  4. Credentials never appear in plain text in log output or run artifacts
**Plans**: 3 plans

Plans:
- [ ] 02-01-PLAN.md -- Credential resolution chain with warning-on-default and interactive fallback (SEC-01)
- [ ] 02-02-PLAN.md -- Replace SSH UserKnownHostsFile=NUL with lab-specific known_hosts (SEC-02)
- [ ] 02-03-PLAN.md -- Mandatory download checksums and credential scrubbing for logs (SEC-03, SEC-04)

### Phase 3: Core Lifecycle Integration
**Goal**: Bootstrap → Deploy → Use → Teardown completes end-to-end on clean Windows host without errors
**Depends on**: Phase 2
**Requirements**: LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-05, CLI-01, CLI-02, CLI-03, CLI-04, CLI-05, CLI-06, CLI-07, CLI-08, CLI-09, NET-01, NET-02, NET-03, NET-04, NET-05
**Success Criteria** (what must be TRUE):
  1. Bootstrap action installs prerequisites, creates directories, validates environment without errors
  2. Deploy action provisions VMs with correct hardware specs, network config, and domain join
  3. Quick mode restores LabReady snapshot and auto-heals infrastructure gaps reliably
  4. Teardown removes all lab resources cleanly (VMs, checkpoints, vSwitch, NAT) with no orphans
  5. Re-deploy after teardown succeeds (idempotent infrastructure creation)
  6. Health check reports accurate status with actionable diagnostics
  7. All destructive actions require confirmation tokens before executing
  8. Error handling uses try-catch on critical operations with context-aware messages
  9. Network infrastructure (vSwitch, NAT, static IPs, DNS) configures correctly and validates connectivity
**Plans**: 5 plans (3 waves)

Plans:
- [ ] 03-01-PLAN.md -- Fix string interpolation, param syntax, legacy vars in Bootstrap/Deploy/Preflight/Health (LIFE-01, CLI-04)
- [ ] 03-02-PLAN.md -- Add try-catch error handling to all critical Deploy.ps1 sections (CLI-08, LIFE-01)
- [ ] 03-03-PLAN.md -- Fix hardcoded network values, enhance health check with full infrastructure coverage (NET-01..05, CLI-06)
- [ ] 03-04-PLAN.md -- Harden teardown (SSH cleanup, NAT verify), confirmation tokens, bootstrap idempotency (LIFE-04, LIFE-05, CLI-07, CLI-03)
- [ ] 03-05-PLAN.md -- CLI action routing cleanup, quick mode verification, end-to-end integration (LIFE-03, CLI-01, CLI-02, CLI-05, CLI-09)

### Phase 4: Role Provisioning
**Goal**: All 11 Windows/Linux roles provision successfully with graceful error handling
**Depends on**: Phase 3
**Requirements**: ROLE-01, ROLE-02, ROLE-03, ROLE-04, ROLE-05, ROLE-06, ROLE-07, ROLE-08, ROLE-09, ROLE-10, ROLE-11
**Success Criteria** (what must be TRUE):
  1. DC role promotes domain controller with DNS and ADWS services running
  2. SQL role installs SQL Server with configured SA account
  3. IIS, WSUS, DHCP, FileServer, PrintServer, DSC, Jumpbox roles install and configure correctly
  4. Client role joins domain as workstation
  5. All roles handle missing prerequisites gracefully with clear error messages
**Plans**: TBD

Plans:
- [ ] 04-01: [To be planned]

### Phase 5: GUI Integration
**Goal**: WPF GUI provides full feature parity with CLI — all actions accessible and functional from both interfaces
**Depends on**: Phase 4
**Requirements**: GUI-01, GUI-02, GUI-03, GUI-04, GUI-05, GUI-06, GUI-07, GUI-08
**Success Criteria** (what must be TRUE):
  1. Dashboard view loads and polls VM status every 5 seconds without crashes
  2. Actions view populates dropdown and executes all 25+ actions correctly
  3. Customize view loads template editor, creates/saves/applies templates without errors
  4. Settings view persists theme, admin username, preferences to gui-settings.json
  5. Logs view displays color-coded entries from in-memory log list
  6. View switching works reliably between all views without state corruption
  7. Script-scoped variable closures captured correctly in all event handlers
  8. CLI and GUI achieve feature parity — no capability gaps between interfaces
**Plans**: TBD

Plans:
- [ ] 05-01: [To be planned]

### Phase 6: Multi-Host Coordination
**Goal**: Coordinator dispatch routes operations to correct target hosts with scoped safety gates
**Depends on**: Phase 5
**Requirements**: MH-01, MH-02, MH-03, MH-04, MH-05
**Success Criteria** (what must be TRUE):
  1. Host inventory file loads and validates remote host entries
  2. Coordinator dispatch routes operations to correct target hosts
  3. Dispatch modes (off/canary/enforced) behave as documented
  4. Scoped confirmation tokens validate per-host safety gates
  5. Remote operations handle connectivity failures gracefully with clear messages
**Plans**: TBD

Plans:
- [ ] 06-01: [To be planned]

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Cleanup & Config Foundation | 4/4 | Complete | 2026-02-16 |
| 2. Security Hardening | 3/3 | Complete | 2026-02-16 |
| 3. Core Lifecycle Integration | 5/5 | Complete | 2026-02-17 |
| 4. Role Provisioning | 0/0 | Not started | - |
| 5. GUI Integration | 0/0 | Not started | - |
| 6. Multi-Host Coordination | 0/0 | Not started | - |

---
*Roadmap created: 2026-02-16*
*Depth: standard (6 phases)*
*Coverage: 56/56 v1 requirements mapped*
