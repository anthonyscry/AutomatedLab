# Roadmap: AutomatedLab

## Milestones

- ✅ **v1.0 Brownfield Hardening & Integration** - Phases 1-6 (shipped 2026-02-17)
- ✅ **v1.1 Production Robustness** - Phases 7-10 (shipped 2026-02-17)
- ▶ **v1.2 Delivery Readiness** - Phases 11-13 (in progress, started 2026-02-18)

## Phases

<details>
<summary>✅ v1.0 Brownfield Hardening & Integration (Phases 1-6) - SHIPPED 2026-02-17</summary>

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
- [x] 01-01-PLAN.md -- Delete .archive/, untrack artifacts, remove dead code
- [x] 01-02-PLAN.md -- Standardize helper sourcing with fail-fast error handling
- [x] 01-03-PLAN.md -- Unify config to $GlobalLabConfig, add validation, remove legacy vars
- [x] 01-04-PLAN.md -- Template JSON validation on read and write

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
- [x] 02-01-PLAN.md -- Credential resolution chain with warning-on-default and interactive fallback (SEC-01)
- [x] 02-02-PLAN.md -- Replace SSH UserKnownHostsFile=NUL with lab-specific known_hosts (SEC-02)
- [x] 02-03-PLAN.md -- Mandatory download checksums and credential scrubbing for logs (SEC-03, SEC-04)

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
**Plans**: 5 plans

Plans:
- [x] 03-01-PLAN.md -- Fix string interpolation, param syntax, legacy vars in Bootstrap/Deploy/Preflight/Health (LIFE-01, CLI-04)
- [x] 03-02-PLAN.md -- Add try-catch error handling to all critical Deploy.ps1 sections (CLI-08, LIFE-01)
- [x] 03-03-PLAN.md -- Fix hardcoded network values, enhance health check with full infrastructure coverage (NET-01..05, CLI-06)
- [x] 03-04-PLAN.md -- Harden teardown (SSH cleanup, NAT verify), confirmation tokens, bootstrap idempotency (LIFE-04, LIFE-05, CLI-07, CLI-03)
- [x] 03-05-PLAN.md -- CLI action routing cleanup, quick mode verification, end-to-end integration (LIFE-03, CLI-01, CLI-02, CLI-05, CLI-09)

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
**Plans**: 4 plans

Plans:
- [x] 04-01-PLAN.md -- Fix param syntax bugs, add prerequisite validation to DHCP/DSC, create role tests (ROLE-05, ROLE-06, ROLE-08, ROLE-10, ROLE-11)
- [x] 04-02-PLAN.md -- Add error handling and post-install verification to DC/SQL/IIS/WSUS/PrintServer/Jumpbox (ROLE-01, ROLE-02, ROLE-03, ROLE-04, ROLE-07, ROLE-09, ROLE-11)
- [x] 04-03-PLAN.md -- Harden Build-LabFromSelection orchestrator with enhanced reporting and DC-fatal logic (ROLE-11)
- [x] 04-04-PLAN.md -- Add null-guards to Linux role scripts for graceful degradation (ROLE-11)

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
**Plans**: 4 plans

Plans:
- [x] 05-01-PLAN.md -- Actions parity (23 actions), timer lifecycle, view switching try-catch (GUI-01, GUI-02, GUI-06, GUI-07)
- [x] 05-02-PLAN.md -- Logs cap + color fix, full settings persistence, defensive JSON handling (GUI-04, GUI-05)
- [x] 05-03-PLAN.md -- Customize template hardening, blow-away token validation, script path fix (GUI-03, GUI-08)
- [x] 05-04-PLAN.md -- Comprehensive Pester tests for all GUI changes (GUI-01..08)

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
**Plans**: 5 plans

Plans:
- [x] 06-01-PLAN.md -- Host inventory validation: duplicate detection, connection type validation (MH-01)
- [x] 06-02-PLAN.md -- Dispatch routing hardening: empty targets, config-based mode (MH-02, MH-03)
- [x] 06-03-PLAN.md -- Scoped confirmation token edge case tests (MH-04)
- [x] 06-04-PLAN.md -- Remote failure handling: SSH patterns, fleet probe messages (MH-05)
- [x] 06-05-PLAN.md -- End-to-end integration tests for full coordinator pipeline (MH-01..05)

</details>

### v1.1 Production Robustness (Complete)

**Milestone Goal:** Every function handles errors explicitly, the orchestrator is modular and testable, and all 10 known production gaps are closed — so deploys either succeed or explain exactly why they failed.

**Phase Numbering:**
- Integer phases (7, 8, 9, 10): Planned milestone work
- Decimal phases (7.1, 7.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 7: Security & Reliability Fixes** - Close 8 production gaps in security and reliability (S1-S4, R1-R4)
- [x] **Phase 8: Orchestrator Extraction** - Extract 31 inline functions from OpenCodeLab-App.ps1 to Private/ helpers
- [x] **Phase 9: Error Handling** - Add try-catch error handling to all 39 functions currently missing it
- [x] **Phase 10: Module Diagnostics** - Reconcile module exports and replace Out-Null with Write-Verbose

## Phase Details

### Phase 7: Security & Reliability Fixes
**Goal**: All documented security and reliability production gaps (S1-S4, R1-R4) are closed with no hardcoded credentials, insecure SSH operations, unchecked downloads, or incorrect control flow
**Depends on**: Phase 6
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, REL-01, REL-02, REL-03, REL-04
**Success Criteria** (what must be TRUE):
  1. Initialize-LabVMs.ps1 uses $GlobalLabConfig.Credentials.AdminPassword instead of hardcoded default (S1 closed)
  2. Open-LabTerminal.ps1 uses StrictHostKeyChecking=accept-new instead of =no (S2 closed)
  3. Deploy.ps1 validates Git installer SHA256 checksum after download (S3 closed)
  4. New-LabUnattendXml emits Write-Warning about plaintext password storage in unattend.xml (S4 closed)
  5. Test-DCPromotionPrereqs always executes network connectivity check without early return skip (R1 closed)
  6. Ensure-VMsReady uses return instead of exit 0 to avoid premature script termination (R2 closed)
  7. New-LabNAT and Set-VMStaticIP validate IP addresses and CIDR prefix before applying configuration (R3 closed)
  8. Initialize-LabVMs and New-LabSSHKey use $GlobalLabConfig paths instead of hardcoded paths (R4 closed)
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md -- Close security gaps S1-S4: plaintext password warning + verification tests
- [x] 07-02-PLAN.md -- Close reliability gaps R1-R4: control flow, validation, config paths + tests

### Phase 8: Orchestrator Extraction
**Goal**: OpenCodeLab-App.ps1 orchestrator is modular and testable with all 34 inline functions extracted to Private/ helpers
**Depends on**: Phase 7
**Requirements**: EXT-01, EXT-02, EXT-03, EXT-04
**Success Criteria** (what must be TRUE):
  1. All 34 inline functions moved from OpenCodeLab-App.ps1 to Private/ helpers with proper naming conventions
  2. Lab-Common.ps1 auto-loads extracted helpers via Get-LabScriptFiles (no explicit registration needed)
  3. Each extracted helper has [CmdletBinding()], explicit parameters, and no script-scope variable dependencies
  4. All 566 existing Pester tests continue passing after extraction (no behavior regression)
  5. Extracted helpers are independently testable with unit tests
**Plans**: 4 plans

Plans:
- [x] 08-01-PLAN.md -- Extract 11 pure utility functions (arg builders, script resolver, run events, log retention)
- [x] 08-02-PLAN.md -- Extract 8 state/operation functions (state overrides, snapshots, VM stop, artifacts, blow-away, quick ops)
- [x] 08-03-PLAN.md -- Extract 6 lifecycle orchestration functions (action core, one-button setup/reset, setup, bulk VM)
- [x] 08-04-PLAN.md -- Extract 9 interactive menu functions (menu display, commands, role config, VM wizard)

### Phase 9: Error Handling
**Goal**: All functions without try-catch get explicit error handling with context-aware messages
**Depends on**: Phase 8
**Requirements**: ERR-01, ERR-02, ERR-03, ERR-04
**Success Criteria** (what must be TRUE):
  1. All 34 Private functions without try-catch (excluding 15 trivial/exempt) have explicit error handling added
  2. All 6 Public functions without try-catch have explicit error handling added
  3. Error messages include function name and actionable context (not just stack traces)
  4. No function uses exit to terminate — all use return or throw for proper error propagation
  5. Error handling follows PowerShell best practices (ErrorAction, ErrorRecord, terminating vs non-terminating)
**Plans**: 4 plans

Plans:
- [ ] 09-01-PLAN.md -- Add try-catch to 10 orchestration & lifecycle Private functions (ERR-01, ERR-03)
- [ ] 09-02-PLAN.md -- Add try-catch to 10 configuration & data-building Private functions (ERR-01, ERR-03)
- [ ] 09-03-PLAN.md -- Add try-catch to 14 resolution, policy & menu Private functions (ERR-01, ERR-03)
- [ ] 09-04-PLAN.md -- Add try-catch to 6 Public functions + comprehensive audit tests (ERR-01, ERR-02, ERR-03, ERR-04)

### Phase 10: Module Diagnostics
**Goal**: Module export list is accurate and diagnostic visibility is maximized without suppressing useful output
**Depends on**: Phase 9
**Requirements**: DIAG-01, DIAG-02, DIAG-03
**Success Criteria** (what must be TRUE):
  1. All Out-Null instances replaced with context-appropriate patterns in operational paths (diagnostic visibility)
  2. SimpleLab.psd1 FunctionsToExport matches actual Public/ function count (export reconciliation)
  3. SimpleLab.psm1 Export-ModuleMember matches .psd1 FunctionsToExport list (consistency)
  4. Module loads without warnings about missing or extra exported functions
**Plans**: 3 plans

Plans:
- [x] 10-01-PLAN.md -- GUI [void] cast conversion + module export reconciliation + regression tests (DIAG-02, DIAG-03)
- [x] 10-02-PLAN.md -- Replace Out-Null in Private/ and Public/ files with context-aware patterns (DIAG-01)
- [x] 10-03-PLAN.md -- Replace Out-Null in Deploy, Bootstrap, LabBuilder, Scripts with context-aware patterns (DIAG-01)

## v1.2 Delivery Readiness (In Progress)

**Milestone Goal:** Prepare for safe shipping and adoption by improving delivery docs, release automation, and public API test coverage.

### Phase 11: Documentation and Onboarding

**Goal:** Ensure users and operators have clear, current documentation for all key workflows.
**Depends on**: Phase 10
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04
**Success Criteria** (what must be TRUE):
  1. README/entry docs match current CLI and GUI behavior.
  2. User guide includes bootstrap, deploy, quick mode, and teardown workflows with expected outputs.
  3. Troubleshooting guide covers common production failure modes and recovery sequence.
  4. Every Public function includes help comments with example usage.
  5. Documentation accuracy is validated against runtime behavior in at least one integration check.
**Plans**:
- [ ] 11-01-PLAN.md -- Refresh README and onboarding docs to reflect v1.1 behavior
- [ ] 11-02-PLAN.md -- Write lifecycle user guide and troubleshooting playbook
- [ ] 11-03-PLAN.md -- Add/update Public function help comments and examples

### Phase 12: CI/CD and Release Automation

**Goal:** Add release-quality automation so quality gates run automatically before changes ship.
**Depends on**: Phase 11
**Requirements**: CICD-01, CICD-02, CICD-03, CICD-04
**Success Criteria** (what must be TRUE):
  1. PR pipeline runs full Pester suite and fails with actionable logs.
  2. Static analysis runs in CI with project-specific baseline exceptions only.
  3. Release workflow verifies versioning, build, and artifact integrity.
  4. Publish flow for PowerShell Gallery includes reviewable metadata and permissions controls.
  5. CI can run on clean agents without manual intervention.
**Plans**:
- [ ] 12-01-PLAN.md -- Add PR test workflow for Pester and failure reporting
- [ ] 12-02-PLAN.md -- Add ScriptAnalyzer workflow with lint baseline
- [ ] 12-03-PLAN.md -- Build and release automation with version/artifact checks

### Phase 13: Test Coverage Expansion

**Goal:** Improve confidence in public APIs and end-to-end reliability with focused tests.
**Depends on**: Phase 12
**Requirements**: TEST-01, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. 20+ previously untested Public functions have passing unit tests.
  2. Coverage reporting runs in CI and enforces a defined threshold.
  3. E2E smoke test validates bootstrap/deploy/teardown outcome with stable exit conditions.
  4. Traceability from requirements to test artifacts is explicit.
**Plans**:
- [ ] 13-01-PLAN.md -- Add tests for untested Public functions and coverage baselines
- [ ] 13-02-PLAN.md -- Add coverage reporting and CI enforcement
- [ ] 13-03-PLAN.md -- Add smoke E2E suite for lifecycle path

## Progress

**Execution Order:**
Phases execute in numeric order: 7 → 8 → 9 → 10 → 11 → 12 → 13

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Cleanup & Config Foundation | v1.0 | 4/4 | Complete | 2026-02-16 |
| 2. Security Hardening | v1.0 | 3/3 | Complete | 2026-02-16 |
| 3. Core Lifecycle Integration | v1.0 | 5/5 | Complete | 2026-02-17 |
| 4. Role Provisioning | v1.0 | 4/4 | Complete | 2026-02-17 |
| 5. GUI Integration | v1.0 | 4/4 | Complete | 2026-02-17 |
| 6. Multi-Host Coordination | v1.0 | 5/5 | Complete | 2026-02-17 |
| 7. Security & Reliability Fixes | v1.1 | 2/2 | Complete | 2026-02-17 |
| 8. Orchestrator Extraction | v1.1 | 4/4 | Complete | 2026-02-17 |
| 9. Error Handling | v1.1 | 4/4 | Complete | 2026-02-17 |
| 10. Module Diagnostics | v1.1 | 3/3 | Complete | 2026-02-17 |
| 11. Documentation and Onboarding | 4/10 | In Progress|  | — |
| 12. CI/CD and Release Automation | v1.2 | 0/3 | In progress | — |
| 13. Test Coverage Expansion | v1.2 | 0/3 | In progress | — |

---
*Roadmap created: 2026-02-16 (v1.0)*
*v1.1 milestone added: 2026-02-17*
*v1.2 milestone started: 2026-02-18*
*Depth: standard (4 phases for v1.1, 3 phases for v1.2 planned)*
*Coverage: 19/19 v1.1 + 11/11 v1.2 requirements mapped*
