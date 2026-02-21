# Roadmap: AutomatedLab

## Milestones

- ✅ **v1.0 Brownfield Hardening & Integration** - Phases 1-6 (shipped 2026-02-17)
- ✅ **v1.1 Production Robustness** - Phases 7-10 (shipped 2026-02-17)
- ✅ **v1.2 Delivery Readiness** - Phases 11-13 (shipped 2026-02-20)
- ✅ **v1.3 Lab Scenarios & Operator Tooling** - Phases 14-17 (shipped 2026-02-20)
- ✅ **v1.4 Configuration Management & Reporting** - Phases 18-21 (shipped 2026-02-20)
- ✅ **v1.5 Advanced Scenarios & Multi-OS** - Phases 22-25 (shipped 2026-02-21)
- ✅ **v1.6 Lab Lifecycle & Security Automation** - Phases 26-29 (shipped 2026-02-21)
- ✅ **v1.7 Operational Excellence & Analytics** - Phases 30-33 (shipped 2026-02-21)
- ~~v1.8 Cloud Integration & Hybrid Labs~~ - *Cancelled; project complete at v1.7*

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

<details>
<summary>✅ v1.5 Advanced Scenarios & Multi-OS (Phases 22-25) - SHIPPED 2026-02-21</summary>

- [x] Phase 22: Custom Role Templates (2/2 plans) — completed 2026-02-20
- [x] Phase 23: Complex Networking (2/2 plans) — completed 2026-02-20
- [x] Phase 24: Linux VM Parity (2/2 plans) — completed 2026-02-21
- [x] Phase 25: Mixed OS Integration (2/2 plans) — completed 2026-02-21

Full details: `.planning/milestones/v1.5-ROADMAP.md`

</details>

<details>
<summary>✅ v1.6 Lab Lifecycle & Security Automation (Phases 26-29) - SHIPPED 2026-02-21</summary>

- [x] Phase 26: Lab TTL & Lifecycle Monitoring (3/3 plans) — completed 2026-02-21
- [x] Phase 27: PowerSTIG DSC Baselines (5/5 plans) — completed 2026-02-21
- [x] Phase 28: ADMX / GPO Auto-Import (4/4 plans) — completed 2026-02-21
- [x] Phase 29: Dashboard Enrichment (5/5 plans) — completed 2026-02-21

Full details: `.planning/milestones/v1.6-ROADMAP.md`

</details>

<details>
<summary>✅ v1.7 Operational Excellence & Analytics (Phases 30-33) - SHIPPED 2026-02-21</summary>

- [x] Phase 30: Lab Analytics (3/3 plans) — completed 2026-02-21
- [x] Phase 31: Advanced Reporting (3/3 plans) — completed 2026-02-21
- [x] Phase 32: Operational Workflows (4/4 plans) — completed 2026-02-21
- [x] Phase 33: Performance Guidance (3/3 plans) — completed 2026-02-21

Full details: `.planning/milestones/v1.7-ROADMAP.md`

</details>

~~### v1.8 Cloud Integration & Hybrid Labs (Cancelled)~~

*This milestone was planned but cancelled. The project is complete at v1.7.*

## Phase Details

<details>
<summary>✅ Phase 1: Cleanup & Config Foundation - COMPLETE</summary>

**Goal**: Unified configuration foundation with dead code removal and helper sourcing standardization
**Depends on**: Nothing (first phase)
**Requirements**: CONF-01, CONF-02, CONF-03, CONF-04, CONF-05, CONF-06, CONF-07, CONF-08, CONF-09
**Success Criteria** (what must be TRUE):
  1. All unused functions and variables are removed from codebase
  2. Single $GlobalLabConfig hashtable serves as configuration source of truth
  3. All Private/ helpers are automatically sourced via Lab-Common.ps1 discovery
  4. Configuration validation fails fast with clear error messages
**Plans**: 4/4 complete

</details>

<details>
<summary>✅ Phase 2: Security Hardening - COMPLETE</summary>

**Goal**: Explicit password resolution, secure SSH handling, download integrity validation, and log sanitization
**Depends on**: Phase 1
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, SEC-05, SEC-06, SEC-07
**Success Criteria** (what must be TRUE):
  1. Credentials are resolved from multiple sources with clear precedence rules
  2. SSH known_hosts is managed per-lab with accept-new security
  3. All downloaded files are validated against checksums before use
  4. Sensitive data is scrubbed from logs before storage
**Plans**: 3/3 complete

</details>

<details>
<summary>✅ Phase 3: Core Lifecycle Integration - COMPLETE</summary>

**Goal**: End-to-end bootstrap, deploy, and teardown workflows with error handling and string interpolation fixes
**Depends on**: Phase 1, Phase 2
**Requirements**: LIFE-01, LIFE-02, LIFE-03, LIFE-04, LIFE-05
**Success Criteria** (what must be TRUE):
  1. Bootstrap process completes from lab definition to ready-to-deploy state
  2. Deployment provisions all VMs with roles and reports clear progress
  3. Teardown removes all lab artifacts including VMs, networks, and files
  4. All string interpolation uses proper subexpression syntax
**Plans**: 5/5 complete

</details>

<details>
<summary>✅ Phase 4: Role Provisioning - COMPLETE</summary>

**Goal**: All 16 LabBuilder roles provisioned with try-catch error handling and verification
**Depends on**: Phase 3
**Requirements**: ROLE-01, ROLE-02, ROLE-03, ROLE-04
**Success Criteria** (what must be TRUE):
  1. All 16 roles install prerequisites without failure
  2. Role PostInstall scripts complete with error handling
  3. Role installation is verified after completion
  4. Failed role provisions are clearly reported with actionable error messages
**Plans**: 4/4 complete

</details>

<details>
<summary>✅ Phase 5: GUI Integration - COMPLETE</summary>

**Goal**: GUI actions have parity with CLI, theme-safe colors, settings persistence, and customize dialog hardening
**Depends on**: Phase 4
**Requirements**: GUI-01, GUI-02, GUI-03, GUI-04, GUI-05
**Success Criteria** (what must be TRUE):
  1. All GUI actions complete equivalent CLI operations successfully
  2. GUI color scheme switches between themes without errors
  3. GUI settings persist across application restarts
  4. Customize dialog validates all inputs before applying changes
**Plans**: 4/4 complete

</details>

<details>
<summary>✅ Phase 6: Multi-Host Coordination - COMPLETE</summary>

**Goal**: Multiple Hyper-V hosts coordinate lab operations with inventory tracking and failure classification
**Depends on**: Phase 5
**Requirements**: MULTI-01, MULTI-02, MULTI-03, MULTI-04, MULTI-05
**Success Criteria** (what must be TRUE):
  1. Host inventory is discovered and maintained across the lab fleet
  2. Operations are dispatched to appropriate hosts based on VM location
  3. Tokens are scoped to target hosts for security
  4. Transient failures are classified and retried appropriately
**Plans**: 5/5 complete

</details>

<details>
<summary>✅ Phase 7: Security & Reliability Fixes - COMPLETE</summary>

**Goal**: Close security gaps S1-S4 and reliability gaps R1-R4 identified in production review
**Depends on**: Phase 6
**Requirements**: REL-01, REL-02, REL-03, REL-04, REL-05, REL-06, REL-07, REL-08
**Success Criteria** (what must be TRUE):
  1. All identified security and reliability gaps are resolved
  2. Error messages provide actionable guidance
  3. Functions handle edge cases without crashing
  4. Resource cleanup occurs even on errors
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 8: Orchestrator Extraction - COMPLETE</summary>

**Goal**: Extract orchestration logic from monolithic functions into testable, modular helpers
**Depends on**: Phase 7
**Requirements**: ORCH-01, ORCH-02, ORCH-03, ORCH-04
**Success Criteria** (what must be TRUE):
  1. Orchestrator functions are extracted to Private/ with clear responsibilities
  2. Each helper function has unit tests
  3. Orchestrator composition flows are clear and maintainable
  4. Error handling is preserved during extraction
**Plans**: 4/4 complete

</details>

<details>
<summary>✅ Phase 9: Error Handling - COMPLETE</summary>

**Goal**: Complete error handling coverage across Private and Public functions with explicit try-catch
**Depends on**: Phase 8
**Requirements**: ERR-01, ERR-02, ERR-03, ERR-04
**Success Criteria** (what must be TRUE):
  1. All Private/ functions have try-catch blocks
  2. All Public/ functions have try-catch blocks
  3. Error messages are context-specific and actionable
  4. Error handling preserves stack traces for debugging
**Plans**: 4/4 complete

</details>

<details>
<summary>✅ Phase 10: Module Diagnostics - COMPLETE</summary>

**Goal**: Module export correctness and diagnostic cleanup without breaking existing functionality
**Depends on**: Phase 9
**Requirements**: MOD-01, MOD-02, MOD-03
**Success Criteria** (what must be TRUE):
  1. Only intended functions are exported from module manifest
  2. Diagnostic output is removed from production code paths
  3. Module imports cleanly without errors or warnings
**Plans**: 3/3 complete

</details>

<details>
<summary>✅ Phase 11: Documentation and Onboarding - COMPLETE</summary>

**Goal**: Comprehensive documentation suite with quality gates and validation scripts
**Depends on**: Phase 10
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04
**Success Criteria** (what must be TRUE):
  1. README provides clear project overview and quick start path
  2. Getting Started guide walks through first lab deployment
  3. Lifecycle workflows document covers bootstrap, deploy, teardown
  4. Rollback runbook provides recovery procedures
  5. All Public functions have complete help comments
  6. Docs validation script generates evidence report
**Plans**: 10/10 complete

</details>

<details>
<summary>✅ Phase 12: CI/CD and Release Automation - COMPLETE</summary>

**Goal**: Automated testing pipeline and release workflow with controlled permissions
**Depends on**: Phase 11
**Requirements**: CICD-01, CICD-02, CICD-03, CICD-04
**Success Criteria** (what must be TRUE):
  1. GitHub Actions runs Pester tests on every PR
  2. ScriptAnalyzer runs on every PR with rule enforcement
  3. Releases are automated via GitHub Actions on tag push
  4. PowerShell Gallery publish uses controlled permissions
**Plans**: 3/3 complete

</details>

<details>
<summary>✅ Phase 13: Test Coverage Expansion - COMPLETE</summary>

**Goal**: Unit tests for all Public functions, coverage reporting, and E2E smoke test
**Depends on**: Phase 12
**Requirements**: TEST-01, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. All 47 Public functions have unit tests
  2. Coverage report shows measurable coverage percentage
  3. Coverage threshold is enforced in CI pipeline
  4. E2E smoke test validates bootstrap-deploy-teardown lifecycle
**Plans**: 3/3 complete

</details>

<details>
<summary>✅ Phase 14: Lab Scenario Templates - COMPLETE</summary>

**Goal**: Pre-built lab scenario templates as JSON files with CLI integration and resource estimation
**Depends on**: Phase 13
**Requirements**: TMPL-01, TMPL-02, TMPL-03, TMPL-04, TMPL-05
**Success Criteria** (what must be TRUE):
  1. Scenario templates are stored as JSON files in .planning/scenarios/
  2. New templates auto-discover without code changes
  3. Get-LabScenario lists available templates
  4. Deploy-Lab accepts -Scenario parameter
  5. Resource estimation warns before deployment
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 15: Configuration Validation - COMPLETE</summary>

**Goal**: Pre-deployment validation with guided diagnostics and error collection
**Depends on**: Phase 14
**Requirements**: CONF-01, CONF-02, CONF-03
**Success Criteria** (what must be TRUE):
  1. Test-LabConfiguration validates entire config before deployment
  2. Validation errors are collected and reported together
  3. Get-LabConfigurationDiagnostics provides actionable remediation steps
  4. Hyper-V module availability is checked
  5. CPU/RAM/disk constraints are validated
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 16: Snapshot Lifecycle - COMPLETE</summary>

**Goal**: Snapshot inventory, pruning, and status integration with ShouldProcess safety
**Depends on**: Phase 15
**Requirements**: SNAP-01, SNAP-02, SNAP-03
**Success Criteria** (what must be TRUE):
  1. Get-LabSnapshot lists all snapshots across lab VMs
  2. Remove-LabSnapshot deletes snapshots with -WhatIf support
  3. Snapshot age warnings appear on dashboard
  4. Prune operation supports -WhatIf for safety
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 17: GUI Dashboard Enhancements - COMPLETE</summary>

**Goal**: Dashboard health banner, resource summary, and bulk actions
**Depends on**: Phase 16
**Requirements**: DASH-01, DASH-02, DASH-03
**Success Criteria** (what must be TRUE):
  1. Dashboard shows health banner with lab status
  2. Resource summary displays total and per-VM CPU/RAM/disk usage
  3. Bulk actions (start/stop/restart) work on multiple VMs
  4. Dashboard refreshes automatically
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 18: Configuration Profiles - COMPLETE</summary>

**Goal**: Named configuration profiles with save, load, list, delete CRUD operations
**Depends on**: Phase 17
**Requirements**: PROF-01, PROF-02, PROF-03, PROF-04
**Success Criteria** (what must be TRUE):
  1. Save-LabProfile stores configuration to JSON file
  2. Load-LabProfile loads and applies configuration
  3. Get-LabProfile lists available profiles
  4. Remove-LabProfile deletes profile files
  5. Profiles stored in .planning/profiles/
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 19: Run History Tracking - COMPLETE</summary>

**Goal**: Run history tracking via Get-LabRunHistory wrapping existing artifact infrastructure
**Depends on**: Phase 18
**Requirements**: HIST-01, HIST-02, HIST-03
**Success Criteria** (what must be TRUE):
  1. Get-LabRunHistory returns lab deployment history
  2. History includes timestamp, lab name, action type, result
  3. History is automatically logged during deployments
  4. No new logging infrastructure needed
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 20: GUI Log Viewer - COMPLETE</summary>

**Goal**: GUI log viewer with DataGrid, action-type filtering, and text file export
**Depends on**: Phase 19
**Requirements**: LOGV-01, LOGV-02, LOGV-03
**Success Criteria** (what must be TRUE):
  1. Log viewer displays run logs in DataGrid format
  2. Filter by action type (bootstrap, deploy, teardown)
  3. Export filtered logs to text file
  4. Cached history avoids repeated disk reads
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 21: Lab Export/Import - COMPLETE</summary>

**Goal**: Lab export/import with self-contained JSON packages and multi-field integrity validation
**Depends on**: Phase 20
**Requirements**: XFER-01, XFER-02, XFER-03
**Success Criteria** (what must be TRUE):
  1. Export-LabPackage creates self-contained package
  2. Import-LabPackage validates and applies configuration
  3. All fields validated before applying
  4. Errors collected together not fail-fast
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 22: Custom Role Templates - COMPLETE</summary>

**Goal**: Custom role template engine — JSON-defined roles with schema validation, auto-discovery, and full LabBuilder integration
**Depends on**: Phase 21
**Requirements**: ROLE-01, ROLE-02, ROLE-03, ROLE-04, ROLE-05
**Success Criteria** (what must be TRUE):
  1. Custom roles defined as JSON in .planning/roles/
  2. JSON schema validates role files
  3. Invalid files are warned and skipped
  4. Get-LabCustomRole lists available custom roles
  5. LabBuilder menu integrates custom roles
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 23: Complex Networking - COMPLETE</summary>

**Goal**: Multi-switch networking — named vSwitches with VLAN tagging, per-VM switch assignment, pairwise subnet overlap detection, multi-subnet routing
**Depends on**: Phase 22
**Requirements**: NET-01, NET-02, NET-03, NET-04, NET-05
**Success Criteria** (what must be TRUE):
  1. LabConfig supports Switches array for multi-vSwitch
  2. Per-VM switch assignment via SwitchName property
  3. VLAN tagging configured per VM
  4. Subnet overlap detection warns on conflicts
  5. Multi-subnet routing configured automatically
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 24: Linux VM Parity - COMPLETE</summary>

**Goal**: Linux VM full parity — snapshot inventory discovers all Linux VMs, profile metadata, SSH retry with configurable backoff
**Depends on**: Phase 23
**Requirements**: LNX-01, LNX-02, LNX-03, LNX-04, LNX-05, LNX-06
**Success Criteria** (what must be TRUE):
  1. Get-LabSnapshot discovers Linux VMs
  2. Save-LabProfile stores Linux VM metadata
  3. Load-LabProfile restores Linux VM metadata
  4. SSH provisioning retries with exponential backoff
  5. CentOS Stream 9 support added
  6. Retry configurable via LabConfig
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 25: Mixed OS Integration - COMPLETE</summary>

**Goal**: Mixed OS integration — end-to-end scenario template (DC + IIS + Ubuntu + DB), integration tests, lifecycle documentation
**Depends on**: Phase 24
**Requirements**: MIX-01, MIX-02
**Success Criteria** (what must be TRUE):
  1. Mixed OS scenario template works end-to-end
  2. Integration tests validate cross-OS workflows
  3. Documentation covers mixed OS lifecycle
**Plans**: 2/2 complete

</details>

<details>
<summary>✅ Phase 26: Lab TTL & Lifecycle Monitoring - COMPLETE</summary>

**Goal**: Config-driven lab TTL with background task monitoring, auto-suspend, and uptime query
**Depends on**: Phase 25
**Requirements**: TTL-01, TTL-02, TTL-03
**Success Criteria** (what must be TRUE):
  1. LabConfig supports TTL configuration block
  2. TTL monitoring runs as Windows Scheduled Task
  3. Auto-suspend triggers on wall-clock or idle thresholds
  4. Get-LabUptime returns lab uptime
  5. TTL defaults to disabled
**Plans**: 3/3 complete

</details>

<details>
<summary>✅ Phase 27: PowerSTIG DSC Baselines - COMPLETE</summary>

**Goal**: Role-aware DISA STIG DSC baselines auto-applied at deploy time with per-VM exceptions
**Depends on**: Phase 26
**Requirements**: STIG-01, STIG-02, STIG-03, STIG-04, STIG-05, STIG-06
**Success Criteria** (what must be TRUE):
  1. LabConfig supports STIG configuration block
  2. Get-LabSTIGConfig reads STIG settings
  3. STIG profile mapper maps roles to STIG IDs
  4. PowerSTIG pre-flight check validates OS version
  5. DSC MOF compilation produces baselines
  6. Write-LabSTIGCompliance writes cache
  7. Invoke-LabSTIGBaseline applies baselines
  8. Get-LabSTIGCompliance reads cache
  9. STIG defaults to disabled
**Plans**: 5/5 complete

</details>

<details>
<summary>✅ Phase 28: ADMX / GPO Auto-Import - COMPLETE</summary>

**Goal**: ADMX Central Store auto-populate, baseline GPO templates, third-party ADMX, DC PostInstall integration
**Depends on**: Phase 27
**Requirements**: GPO-01, GPO-02, GPO-03, GPO-04
**Success Criteria** (what must be TRUE):
  1. LabConfig supports ADMX configuration block
  2. Get-LabADMXConfig reads ADMX settings
  3. Wait-LabADReady gates on Get-ADDomain
  4. Invoke-LabADMXImport populates Central Store
  5. Four baseline GPO templates (password, lockout, audit, AppLocker)
  6. CreateBaselineGPO support in DC PostInstall
  7. Enabled defaults to true, CreateBaselineGPO false
**Plans**: 4/4 complete

</details>

<details>
<summary>✅ Phase 29: Dashboard Enrichment - COMPLETE</summary>

**Goal**: Dashboard enrichment with snapshot age, disk usage, uptime, STIG status via background runspace
**Depends on**: Phase 28
**Requirements**: DASH-01, DASH-02, DASH-03, DASH-04, DASH-05
**Success Criteria** (what must be TRUE):
  1. Dashboard shows snapshot age with warnings
  2. Dashboard shows disk usage per VM
  3. Dashboard shows VM uptime
  4. Dashboard shows STIG compliance status
  5. 60-second background runspace collects metrics
  6. Synchronized hashtable for thread safety
  7. Get-LabDashboardConfig, Get-LabSnapshotAge, Get-LabVMDiskUsage, Get-LabVMMetrics helpers
  8. VMCard.xaml updated with metrics
**Plans**: 5/5 complete

</details>

<details>
<summary>✅ Phase 30: Lab Analytics - COMPLETE</summary>

**Goal**: Lab usage trends, data export, and automatic event tracking for operational visibility
**Depends on**: Phase 29
**Requirements**: ANLY-01, ANLY-02, ANLY-03
**Success Criteria** (what must be TRUE):
  1. Operator can view lab usage trends over time (VM uptime, resource consumption patterns)
  2. Operator can export lab usage data to CSV/JSON for external analysis
  3. System automatically tracks lab creation, deployment, and teardown events in analytics log
  4. Analytics data persists across PowerShell sessions
**Plans**: 3/3 complete

</details>

<details>
<summary>✅ Phase 31: Advanced Reporting - COMPLETE</summary>

**Goal**: Compliance reports, resource utilization reports, scheduled report generation, and audit trail
**Depends on**: Phase 30
**Requirements**: RPT-01, RPT-02, RPT-03, RPT-04
**Success Criteria** (what must be TRUE):
  1. Operator can generate compliance reports (STIG status across all VMs, pass/fail summary)
  2. Operator can generate resource utilization reports (disk, memory, CPU trends)
  3. Operator can schedule automated report generation (daily/weekly compliance snapshots)
  4. Reports include timestamp, lab name, and summary statistics for audit trail
**Plans**: 3/3 complete

</details>

<details>
<summary>✅ Phase 32: Operational Workflows - COMPLETE</summary>

**Goal**: Bulk VM operations, custom operation workflows, pre-flight validation, and confirmation summaries
**Depends on**: Phase 31
**Requirements**: OPS-01, OPS-02, OPS-03, OPS-04
**Success Criteria** (what must be TRUE):
  1. Operator can perform bulk VM operations (start/stop/suspend multiple VMs at once)
  2. Operator can create custom operation workflows (scripts that combine common actions)
  3. System validates bulk operations before execution (pre-flight checks, resource availability)
  4. Operator receives confirmation summary after bulk operations complete
**Plans**: 4/4 complete

</details>

<details>
<summary>✅ Phase 33: Performance Guidance - COMPLETE</summary>

**Goal**: Performance metrics for VM operations, optimization suggestions, and historical analysis
**Depends on**: Phase 32
**Requirements**: PERF-01, PERF-02, PERF-03
**Success Criteria** (what must be TRUE):
  1. Operator can view performance metrics for VM operations (provision time, snapshot duration)
  2. System provides optimization suggestions when performance degradation detected
  3. Performance data is collected automatically and stored for historical analysis
**Plans**: 3/3 complete

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-6. Brownfield Hardening | v1.0 | 25/25 | Complete | 2026-02-17 |
| 7-10. Production Robustness | v1.1 | 13/13 | Complete | 2026-02-17 |
| 11-13. Delivery Readiness | v1.2 | 16/16 | Complete | 2026-02-20 |
| 14-17. Lab Scenarios & Tooling | v1.3 | 8/8 | Complete | 2026-02-20 |
| 18-21. Config Management | v1.4 | 8/8 | Complete | 2026-02-20 |
| 22-25. Advanced Scenarios | v1.5 | 8/8 | Complete | 2026-02-21 |
| 26-29. Lifecycle & Security | v1.6 | 17/17 | Complete | 2026-02-21 |
| 30-33. Operational Excellence | v1.7 | 13/13 | Complete | 2026-02-21 |

**Total shipped: 108 plans across 33 phases.**
**Project Status: COMPLETE at v1.7**

---
*Roadmap created: 2026-02-16 (v1.0)*
*Project completed: 2026-02-21 (v1.7)*
