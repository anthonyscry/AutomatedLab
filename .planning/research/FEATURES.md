# Feature Research

**Domain:** PowerShell Hyper-V Lab Automation — v1.6 Security Posture & Lifecycle Automation
**Researched:** 2026-02-20
**Confidence:** MEDIUM-HIGH

> **Scope:** This document covers ONLY the v1.6 milestone features. The existing v1.0–v1.5 feature
> landscape is documented in the original FEATURES.md (pre-2026-02-20). The four new feature areas
> are: Lab TTL/auto-suspend, PowerSTIG DSC baselines, ADMX/GPO auto-import, and enriched
> operational dashboard.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features operators assume exist once a lab lifecycle automation tool matures to this level. Missing
these makes the tool feel unfinished for security or enterprise lab use cases.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Lab TTL with configurable timeout** | Long-running labs waste host RAM/CPU; operators expect a knob to set when the lab auto-suspends | MEDIUM | Config-driven (`Lab-Config.ps1` block), not hardcoded. Aligns with existing AutoHeal config pattern. |
| **Scheduled-task-based background monitor** | TTL enforcement requires something watching the clock without a user session; scheduled tasks are the Windows standard | MEDIUM | `Register-ScheduledTask` / `New-ScheduledTaskTrigger` in PS 5.1. Task runs a probe script on an interval. |
| **Graceful VM suspend (not hard stop)** | Operators want to resume labs, not rebuild. Hard shutdown loses in-flight work. | LOW | `Suspend-VM` already in Hyper-V module; wraps cleanly into existing `Stop-LabVMsSafe` pattern. |
| **TTL override / snooze from CLI** | Operators actively using a lab must be able to postpone auto-suspend | LOW | Write a last-active timestamp to a sentinel file; monitor checks age of file. |
| **ADMX central store creation post-DC** | Any AD lab that supports GPO management needs the central store populated; GPO editor is blind without it | MEDIUM | Copy `C:\Windows\PolicyDefinitions` to `\\domain\SYSVOL\domain\Policies\PolicyDefinitions` after DC promotion completes. PowerShell `Copy-Item -Recurse -Force` pattern. Needs DC-ready gate. |
| **OS-native ADMX templates populated** | After DC promotion the central store should reflect the OS version of the DC, not an arbitrary source | LOW | Source is always the DC's local `C:\Windows\PolicyDefinitions`; no download required for baseline. |
| **PowerSTIG module present on target VM** | Applying a DSC STIG baseline requires PowerSTIG (and dependent DSC modules) on the target node | MEDIUM | Needs `Install-Module PowerSTIG` or offline copy-in before `Start-DscConfiguration`. Dependency chain: PowerSTIG requires PSDscResources and several DISA DSC resource modules. |
| **DSC MOF compiled from role context** | Users expect the correct STIG applied per role (DC vs. member server), not a generic baseline | MEDIUM | Role-aware MOF generation: `OsRole = 'DC'` for domain controllers, `OsRole = 'MS'` for everything else. StigVersion selected per OS. |
| **Dashboard shows snapshot age** | Snapshot hygiene is already tracked (v1.3); surfacing age in the main VM card is the obvious next step | LOW | Already have snapshot inventory data (`Get-LabSnapshotInventory`). Add age field to VM card render. |
| **Dashboard shows disk usage** | Disk pressure from snapshots/VHDs is a leading indicator of lab failure; operators expect a warning | LOW | `Get-VM | Select StorageAllocated, StorageUsed` or `Measure-VM` provides this. |
| **Dashboard shows uptime** | Quick sanity check that VMs have been running the expected duration | LOW | `(Get-VM).Uptime` is a `TimeSpan`; format as `Xd Xh Xm`. |

### Differentiators (Competitive Advantage)

Features that set this tool apart from manually-run labs or generic Hyper-V automation scripts.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Role-aware STIG baseline selection** | Automatically selects the right PowerSTIG composite resource (DC vs. MS, Windows Server 2019 vs. 2022) based on the VM's declared role in `Lab-Config.ps1` | HIGH | Requires mapping AutomatedLab role names to PowerSTIG `OsVersion`/`OsRole` pairs. Not obvious from PowerSTIG docs — needs explicit mapping table. |
| **SkipRule overrides per VM in Lab-Config** | PowerSTIG defaults are often too strict for lab VMs (e.g., require smartcard logon). A `StigExceptions` block per VM lets operators keep the STIG spirit while making the lab functional. | MEDIUM | PowerSTIG supports `SkipRule` and `OrgSettings` parameters. Exposing these in `Lab-Config.ps1` is the differentiator. |
| **STIG apply at deploy time, not as a separate step** | Most PowerSTIG guides treat baselines as a post-setup manual exercise. Wiring it into the deploy pipeline makes compliance automatic. | HIGH | Needs `Invoke-LabSTIGBaseline` called from the provisioning flow after VM is domain-joined and role-configured. DSC push mode (no pull server required). |
| **Third-party ADMX support (MSSecurityBaseline, LAPS, Chrome)** | The OS-native templates alone are not enough for a complete security baseline. Auto-importing Microsoft Security Baseline ADMX on DC promotion is a significant time-saver. | HIGH | Requires downloading the MSSecurityBaseline zip or shipping it with the tool. High value, high complexity. Flag for deeper research in phase planning. |
| **TTL policy with per-lab override in Lab-Config** | Azure DevTest Labs style: lab-level TTL in global config, per-lab override in `Lab-Config.ps1`. Operator controls granularly. | MEDIUM | Pattern: global default in `Lab-Config.ps1` `LabTTL` block; local override via `-TTLHours` param on `Start-Lab`. |
| **Compliance column in dashboard** | Surfacing `Test-DscConfiguration` pass/fail per VM alongside the existing health banner turns the dashboard into an operational compliance view | HIGH | Requires running `Test-DscConfiguration` inside the guest or via `Invoke-Command` — adds latency. Consider async/cached result with last-checked timestamp. |
| **Background monitor as uninstallable scheduled task** | Lab cleanup on teardown should remove the scheduled task. Operators expect no leftover noise on the host. | LOW | `Unregister-ScheduledTask` in teardown flow. Simple but critical for cleanliness. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Pull server / DSC compliance server** | "Real enterprise uses a pull server" | Massive infrastructure overhead for a single-host lab; adds WinRM/HTTPS configuration, SQL or file share, certificate management | Use DSC push mode: compile MOF on host, push via `Start-DscConfiguration -ComputerName` or `Invoke-Command`. No pull server needed. |
| **Auto-remediate compliance drift continuously** | "Keep VMs always compliant" | Re-applying STIG baselines on a schedule can break running workloads, disrupt domain replication, or fight with role-specific settings | Apply once at deploy time. Provide `Invoke-LabRefreshSTIG` as an operator-triggered command for deliberate re-apply. |
| **Download ADMX templates from internet at deploy time** | "Always use latest templates" | Network dependency in a lab that may be airgapped; version drift between lab runs causes GPO inconsistency | Ship a vendored copy of the ADMX templates with the tool, or prompt once to download and cache in `.planning/admx-cache/`. |
| **Live compliance polling in dashboard (sub-minute)** | "Real-time compliance status" | `Test-DscConfiguration` takes 10–60 seconds per VM; polling it continuously makes the dashboard unusable | Cache compliance result with a timestamp; refresh on demand or on a 5-minute background interval. |
| **TTL-based auto-teardown (destroy VMs)** | "Free up disk automatically" | Irreversible data loss if the operator didn't export or snapshot. Auto-suspend is recoverable; auto-teardown is not. | Auto-suspend only. Teardown requires explicit operator action. TTL-based teardown is explicitly out of scope per PROJECT.md constraints. |
| **DSC pull server for audit trail** | "Compliance history tracking" | Significant infrastructure for a lab; reporting complexity exceeds value | Use `Get-DscConfigurationStatus` per VM, write result to run artifact JSON alongside existing run history pattern. |

---

## Feature Dependencies

```
[Lab TTL Config in Lab-Config.ps1]
    └──drives──> [Invoke-LabTTLMonitor (background probe)]
                     └──calls──> [Suspend-VM (Hyper-V)]
                     └──reads──> [TTL sentinel file (last-active timestamp)]
                                     └──updated-by──> [Invoke-LabTTLTouch (snooze)]

[VM Deploy Flow (existing Invoke-LabDeploy)]
    └──calls (new)──> [Invoke-LabSTIGBaseline]
                          └──requires──> [PowerSTIG module on VM]
                          └──requires──> [VM is domain-joined or standalone]
                          └──reads──> [VM Role from Lab-Config.ps1]
                                          └──maps-to──> [OsRole: DC or MS]
                                          └──maps-to──> [OsVersion: 2016/2019/2022]

[DC Promotion completion (existing)]
    └──triggers (new)──> [Invoke-LabADMXImport]
                              └──reads──> [C:\Windows\PolicyDefinitions on DC]
                              └──writes-to──> [SYSVOL\...\PolicyDefinitions]
                              └──optionally-copies──> [Vendored ADMX cache]

[Dashboard VM Card (existing WPF)]
    └──enriched-by (new)──> [Get-LabVMEnrichedStatus]
                                 └──adds──> [SnapshotAge]
                                 └──adds──> [DiskUsageGB]
                                 └──adds──> [Uptime]
                                 └──adds──> [ComplianceResult (cached)]
                                                └──sourced-from──> [Test-DscConfiguration result]
```

### Dependency Notes

- **Invoke-LabSTIGBaseline requires PowerSTIG on VM**: Must install-module or copy modules to guest before attempting MOF compile+apply. This is the primary complexity driver for STIG features.
- **ADMX import requires DC-ready gate**: DC promotion must be complete and SYSVOL replicated before writing to PolicyDefinitions. Existing `Test-DCPromotionPrereqs` can be reused as a precondition.
- **Dashboard enrichment has no hard dependencies**: Snapshot age, disk, and uptime fields are read-only queries against existing Hyper-V data. Can ship independently of STIG/TTL work.
- **TTL monitor depends on Lab-Config.ps1 TTL block**: If no TTL is configured, the monitor should be a no-op (no task registered). Config-absence means opt-out.
- **Compliance column depends on STIG baseline having been applied**: Showing `Test-DscConfiguration` results for a VM where no MOF was ever applied is meaningless. Display `N/A` until baseline applied.

---

## MVP Definition

### v1.6 Launch With

The minimum set that delivers value across all four stated feature areas.

- [ ] **TTL config block in Lab-Config.ps1** — Establishes the config surface for all TTL features
- [ ] **Invoke-LabTTLMonitor** — Background scheduled task that checks uptime and suspends if TTL exceeded
- [ ] **Invoke-LabTTLTouch** — Operator command to reset TTL countdown ("I'm still using this")
- [ ] **TTL task cleanup on teardown** — `Unregister-ScheduledTask` in teardown path; no host noise left behind
- [ ] **Invoke-LabADMXImport** — Post-DC-promotion step that copies OS ADMX templates to central store
- [ ] **Invoke-LabSTIGBaseline (push mode, OS-native templates only)** — Role-aware DSC push for Windows Server 2019/2022 DC+MS roles; no third-party ADMX
- [ ] **StigExceptions block in Lab-Config.ps1** — Per-VM SkipRule list so labs remain functional
- [ ] **Dashboard: snapshot age + disk usage + uptime fields** — Low-complexity enrichment of existing VM cards
- [ ] **Dashboard: compliance status column (cached)** — `Test-DscConfiguration` result with last-checked timestamp

### Add After v1.6 Ships

- [ ] **Third-party ADMX auto-import (MSSecurityBaseline, LAPS)** — Trigger: operators requesting GPO baseline templates beyond OS defaults. High value but high complexity.
- [ ] **Compliance result written to run artifact JSON** — Trigger: operators wanting audit trail of baseline state at deploy time.
- [ ] **TTL notification (event log or GUI banner)** — Trigger: operators surprised by suspended labs.

### Future Consideration (v2+)

- [ ] **Offline/vendored ADMX cache** — Defer until airgap lab use case is confirmed
- [ ] **Compliance history dashboard** — Defer: requires run artifact schema changes and reporting infrastructure
- [ ] **PowerSTIG for SQL Server / IIS roles** — Defer: niche within niche; validate Windows OS STIG demand first

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Dashboard: snapshot age + disk + uptime | HIGH | LOW | P1 |
| TTL config + monitor + suspend | HIGH | MEDIUM | P1 |
| ADMX central store import (OS templates) | HIGH | LOW | P1 |
| Invoke-LabSTIGBaseline (DC+MS, WS2019/2022) | HIGH | HIGH | P1 |
| StigExceptions block in Lab-Config.ps1 | HIGH | LOW | P1 |
| TTL snooze (touch) command | MEDIUM | LOW | P1 |
| TTL task cleanup on teardown | HIGH | LOW | P1 |
| Dashboard compliance column (cached) | MEDIUM | MEDIUM | P2 |
| Third-party ADMX import (MSSecBaseline) | MEDIUM | HIGH | P2 |
| Compliance result in run artifact | LOW | LOW | P2 |
| TTL notification (banner/event log) | LOW | LOW | P3 |
| Compliance history dashboard | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for v1.6 launch
- P2: Add when core is stable
- P3: Future milestone

---

## Known Complexity Flags

### PowerSTIG Module Distribution
PowerSTIG and its dependency chain (`PSDscResources`, `AuditPolicyDsc`, `SecurityPolicyDsc`, etc.)
must be present on each target VM before a MOF can be applied. For a lab with internet access,
`Install-Module PowerSTIG -Force` inside the guest works. For offline labs, modules must be
pre-staged or copied in during provisioning. This is the primary implementation risk for STIG
features. Needs a dedicated probe — `Test-LabSTIGDependencies` — to check before attempting apply.

### PowerSTIG OsVersion Mapping Gap
The published PowerSTIG wiki documents `OsVersion` values of `'2012R2'` and `'2016'`, but
PowerShell Gallery version 4.22.0 (current as of mid-2024) adds 2019 and 2022 support. The
`OsVersion` string format must be confirmed by inspecting the installed module manifest, not the
wiki. Flag this as a research step within the STIG baseline phase.

### ADMX Copy Permissions
Copying to `\\domain\SYSVOL\domain\Policies\PolicyDefinitions` over the network path requires
Domain Admin rights. The provisioning account already holds these, but the script must run in the
context of that account. Using the local path `C:\Windows\SYSVOL\sysvol\<domain>\Policies\` on the
DC avoids the network share permission edge case. Prefer local path in implementation.

### DSC Compliance Scan Latency
`Test-DscConfiguration` via `Invoke-Command` takes 10–60 seconds per VM depending on the number
of resources in the MOF. Running it synchronously in the dashboard refresh would make the UI
unresponsive. The compliance column must use a cache file written by a background job, not a
live query.

---

## Sources

- [PowerSTIG GitHub Repository](https://github.com/microsoft/PowerStig) — HIGH confidence
- [PowerSTIG Getting Started Wiki](https://github.com/microsoft/PowerStig/wiki/GettingStarted) — HIGH confidence
- [PowerSTIG WindowsServer Composite Resource](https://github.com/microsoft/PowerStig/wiki/WindowsServer) — HIGH confidence (wiki documents 2012R2/2016; Gallery 4.22.0 extends to 2019/2022)
- [PowerSTIG v4.22.0 on PowerShell Gallery](https://www.powershellgallery.com/packages/PowerSTIG/4.22.0) — HIGH confidence
- [ADMX Central Store: Create and Manage — Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store) — HIGH confidence
- [ADMX Central Store Configuration — Windows OS Hub](https://woshub.com/gpo-central-store-admx-templates/) — MEDIUM confidence
- [Azure DevTest Labs Auto-Shutdown Policy](https://learn.microsoft.com/en-us/azure/devtest-labs/devtest-lab-auto-shutdown) — MEDIUM confidence (cloud product, pattern applies to local lab)
- [Suspend-VM Cmdlet — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/hyper-v/suspend-vm?view=windowsserver2025-ps) — HIGH confidence
- [Register-ScheduledTask — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps) — HIGH confidence
- [Test-DscConfiguration — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/psdesiredstateconfiguration/test-dscconfiguration?view=dsc-1.1) — HIGH confidence
- [Get-DscConfigurationStatus — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/psdesiredstateconfiguration/get-dscconfigurationstatus?view=dsc-1.1) — HIGH confidence
- [Measure-VM (Hyper-V) — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/hyper-v/measure-vm?view=windowsserver2025-ps) — HIGH confidence

---
*Feature research for: AutomatedLab v1.6 — Lab Lifecycle & Security Automation*
*Researched: 2026-02-20*
