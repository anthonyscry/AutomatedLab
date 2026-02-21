# Roadmap: AutomatedLab

## Milestones

- ✅ **v1.0 Brownfield Hardening & Integration** - Phases 1-6 (shipped 2026-02-17)
- ✅ **v1.1 Production Robustness** - Phases 7-10 (shipped 2026-02-17)
- ✅ **v1.2 Delivery Readiness** - Phases 11-13 (shipped 2026-02-20)
- ✅ **v1.3 Lab Scenarios & Operator Tooling** - Phases 14-17 (shipped 2026-02-20)
- ✅ **v1.4 Configuration Management & Reporting** - Phases 18-21 (shipped 2026-02-20)
- ✅ **v1.5 Advanced Scenarios & Multi-OS** - Phases 22-25 (shipped 2026-02-21)
- 🚧 **v1.6 Lab Lifecycle & Security Automation** - Phases 26-29 (in progress)

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

### 🚧 v1.6 Lab Lifecycle & Security Automation (In Progress)

**Milestone Goal:** Config-driven lab TTL with background task monitoring, role-aware DISA STIG DSC baselines auto-applied at deploy time, ADMX/GPO auto-import after DC promotion, and enriched operational dashboard consuming all new data sources.

- [x] **Phase 26: Lab TTL & Lifecycle Monitoring** - Config-driven auto-suspend with background scheduled task and uptime query (completed 2026-02-21)
- [ ] **Phase 27: PowerSTIG DSC Baselines** (4 plans) - Role-aware STIG baselines applied at deploy time with per-VM exception overrides and compliance cache
- [ ] **Phase 28: ADMX / GPO Auto-Import** - ADMX Central Store population and baseline GPO creation after DC promotion
- [ ] **Phase 29: Dashboard Enrichment** - Snapshot age, disk usage, uptime, and STIG compliance columns with background runspace data collection

## Phase Details

### Phase 26: Lab TTL & Lifecycle Monitoring
**Goal**: Operators can configure a TTL for the lab and have VMs auto-suspended by a background scheduled task when the TTL expires, with lab uptime queryable at any time
**Depends on**: Nothing (first phase of v1.6)
**Requirements**: TTL-01, TTL-02, TTL-03
**Success Criteria** (what must be TRUE):
  1. Operator sets TTL duration in Lab-Config.ps1 (IdleMinutes, WallClockHours, Action) and the config is loaded without error when keys are absent (ContainsKey guards prevent StrictMode failures)
  2. Running Register-LabTTLTask creates a Windows Scheduled Task visible in Task Scheduler that calls Invoke-LabTTLMonitor; re-running the command is idempotent (unregister-then-register, no duplicate task error)
  3. When TTL expires the scheduled task fires under SYSTEM context and all lab VMs transition to Saved or Off state — no manual intervention required
  4. Get-LabUptime returns lab start time, elapsed hours, and TTL remaining for the running lab
  5. Lab teardown (Remove-Lab or equivalent) calls Unregister-LabTTLTask and leaves no orphaned scheduled tasks on the host
**Plans:** 3/3 plans complete
- [ ] 26-01-PLAN.md — TTL config block and safe config reader (TTL-01)
- [ ] 26-02-PLAN.md — Scheduled task registration and unregistration (TTL-02)
- [ ] 26-03-PLAN.md — TTL monitor, uptime query, and teardown integration (TTL-02, TTL-03)

### Phase 27: PowerSTIG DSC Baselines
**Goal**: Windows Server VMs receive role-appropriate DISA STIG DSC baselines automatically during PostInstall, with per-VM exception overrides and a compliance cache file that downstream tooling can read
**Depends on**: Phase 26 (establishes $GlobalLabConfig block pattern)
**Requirements**: STIG-01, STIG-02, STIG-03, STIG-04, STIG-05, STIG-06
**Success Criteria** (what must be TRUE):
  1. During PostInstall, PowerSTIG 4.28.0 and its 10-module dependency chain install on the target guest VM under -Scope AllUsers (machine scope) — a Test-PowerStigInstallation pre-flight check passes before any MOF compilation begins
  2. A role-appropriate STIG MOF compiles and applies via DSC push mode for DC VMs (OsRole DC) and member server VMs (OsRole MS) using the correct Windows Server 2019/2022 OsVersion string discovered at runtime from StigData/Processed/
  3. WinRM MaxEnvelopeSizekb is raised to 8192 on each target VM before Start-DscConfiguration is called — large MOF delivery does not fail
  4. After STIG application, compliance status is written to .planning/stig-compliance.json with per-VM results and a last-checked timestamp
  5. Per-VM STIG exception overrides declared in the Lab-Config.ps1 STIG block are applied at compile time — specified rules are skipped without affecting other VMs
  6. Operator can run Invoke-LabSTIGBaseline -VMName <name> on demand to re-apply baselines; Get-LabSTIGCompliance returns a per-VM compliance table from the cached JSON
**Plans**: 4 plans
- [ ] 27-01-PLAN.md -- STIG config block and safe config reader (STIG-04)
- [ ] 27-02-PLAN.md -- STIG profile mapper and PowerSTIG pre-flight check (STIG-01, STIG-02)
- [ ] 27-03-PLAN.md -- Core STIG baseline engine and compliance cache writer (STIG-01, STIG-02, STIG-03, STIG-05)
- [ ] 27-04-PLAN.md -- Public cmdlets and PostInstall integration (STIG-05, STIG-06)

### Phase 28: ADMX / GPO Auto-Import
**Goal**: After DC promotion completes, the ADMX Central Store is automatically populated and optional baseline GPOs are created and linked to the domain root from JSON template definitions
**Depends on**: Phase 27 (DC PostInstall step 4 follows step 3 established in Phase 27)
**Requirements**: GPO-01, GPO-02, GPO-03, GPO-04
**Success Criteria** (what must be TRUE):
  1. After DC promotion, a Wait-LabADReady helper gates on Get-ADDomain success (not just WinRM responsiveness) before any ADMX or GPO operations begin — ADWS startup race is eliminated
  2. Invoke-LabADMXImport copies OS ADMX/ADML files from the DC's own C:\Windows\PolicyDefinitions to the SYSVOL Central Store — Group Policy Management Console shows the imported templates with no version conflict errors
  3. When CreateBaselineGPO is enabled in the ADMX config block, a baseline GPO is created via New-GPO, linked to the domain root via New-GPLink, and configured from the shipped JSON template (password policy, account lockout, audit policy, AppLocker)
  4. The four pre-built security GPO JSON templates ship with the project and are importable by Invoke-LabADMXImport without additional operator configuration
  5. Third-party ADMX bundles placed in the configured path are copied to the Central Store when ThirdPartyADMX entries are present in the config — the feature is disabled by default and no download-from-internet behavior occurs
**Plans**: TBD

### Phase 29: Dashboard Enrichment
**Goal**: The GUI dashboard VM cards display snapshot age, disk usage, uptime, and STIG compliance status — all collected by a background runspace so the UI thread never freezes
**Depends on**: Phase 27 (compliance cache), Phase 26 (uptime data), Phase 28 (AD/DC context)
**Requirements**: DASH-01, DASH-02, DASH-03, DASH-04, DASH-05
**Success Criteria** (what must be TRUE):
  1. Each VM card on the dashboard displays the age of its oldest snapshot (in days) with a visual staleness warning when the age exceeds the configured threshold
  2. Each VM card shows current VHDx disk usage in GB with a disk pressure indicator when usage crosses a configurable threshold
  3. Each VM card shows VM uptime (time since last boot) with a stale-threshold alert when the VM has been running longer than the configured limit
  4. Each VM card shows a STIG compliance status field (Compliant / Non-Compliant / Unknown / Applying) read from .planning/stig-compliance.json — the field never triggers a live DSC query from the dashboard
  5. Enriched metrics are collected by a 60-second background runspace pushing to a synchronized hashtable; the existing 5-second DispatcherTimer heartbeat is unchanged and the UI thread does not block during Hyper-V I/O operations
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-6. Brownfield Hardening | v1.0 | 25/25 | Complete | 2026-02-17 |
| 7-10. Production Robustness | v1.1 | 13/13 | Complete | 2026-02-17 |
| 11-13. Delivery Readiness | v1.2 | 16/16 | Complete | 2026-02-20 |
| 14-17. Lab Scenarios & Tooling | v1.3 | 8/8 | Complete | 2026-02-20 |
| 18-21. Config Management | v1.4 | 8/8 | Complete | 2026-02-20 |
| 22-25. Advanced Scenarios | v1.5 | 8/8 | Complete | 2026-02-21 |
| 26. Lab TTL & Lifecycle Monitoring | 2/3 | Complete    | 2026-02-21 | - |
| 27. PowerSTIG DSC Baselines | 2/4 | In Progress|  | - |
| 28. ADMX / GPO Auto-Import | v1.6 | 0/? | Not started | - |
| 29. Dashboard Enrichment | v1.6 | 0/? | Not started | - |

**Total shipped: 78 plans across 25 phases.**

---
*Roadmap created: 2026-02-16 (v1.0)*
*v1.1 milestone added: 2026-02-17*
*v1.2 milestone shipped: 2026-02-20*
*v1.3 milestone shipped: 2026-02-20*
*v1.4 milestone shipped: 2026-02-20*
*v1.5 milestone shipped: 2026-02-21*
*v1.6 milestone added: 2026-02-20*
