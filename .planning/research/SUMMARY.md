# Project Research Summary

**Project:** AutomatedLab v1.6 — Lab Lifecycle & Security Automation
**Domain:** PowerShell/Hyper-V Windows Domain Lab Automation
**Researched:** 2026-02-20
**Confidence:** HIGH

## Executive Summary

AutomatedLab v1.6 is a security posture and lifecycle automation milestone for an existing PowerShell/Hyper-V lab automation framework. The milestone adds four distinct capabilities — lab TTL auto-suspend, PowerSTIG DISA STIG DSC baselines, ADMX/GPO auto-import, and enriched operational dashboard metrics — all within the existing PS 5.1 architecture. The approach is additive: all new features are gated by `Enabled = $false` config flags in `$GlobalLabConfig`, preserving existing behavior by default. No new external dependencies are required on the Hyper-V host; the only new module dependency (PowerSTIG and its DSC resource chain) installs on guest VMs during the existing PostInstall provisioning step.

The recommended implementation path leads with TTL / lifecycle monitoring (most self-contained, establishes the config block pattern for the other three features), follows with PowerSTIG DSC baselines (the highest complexity item, builds on the proven `DSCPullServer.ps1` gallery-install-on-target pattern), then ADMX/GPO import (depends on the DC PostInstall pattern established by the STIG phase), and finishes with dashboard enrichment (consumes compliance state written by the STIG feature and TTL uptime data). Phases can be developed independently due to `Enabled` flag gating, but the dependency chain makes the above ordering strongly recommended.

The critical risks are concentrated in two areas: the PowerSTIG DSC integration (module scope/SYSTEM context, WinRM envelope size, LCM pending state, STIG version mismatch) and the background monitoring infrastructure (scheduled task working directory, idempotency, missing config keys under `Set-StrictMode`). All eleven documented pitfalls have specific, actionable prevention strategies and none require architectural pivots. The dashboard enrichment feature carries a UI-thread freeze risk that requires a background runspace with synchronized hashtable pattern from the outset — retrofitting this pattern after the fact is expensive and disruptive.

## Key Findings

### Recommended Stack

The project is locked to Windows PowerShell 5.1 throughout — a hard constraint driven by Hyper-V module coverage and the existing codebase. DSC v3 (PS 7+ only) is explicitly out of scope. All v1.6 stack additions respect this constraint.

**Core technologies (v1.6 additions):**
- **PowerSTIG 4.28.0** — DISA STIG DSC composite resources per VM role — the only Microsoft-maintained STIG automation module; quarterly release cadence; PS 5.1 minimum confirmed on PSGallery
- **ScheduledTasks module (built-in, Windows 8.1+)** — Windows Task Scheduler via `Register-ScheduledTask` for persistent TTL monitoring — survives session termination, visible in Task Scheduler UI, no install needed
- **GroupPolicy module (built-in on DC)** — `Import-GPO`, `New-GPO`, `New-GPLink` for ADMX/GPO operations — invoked via `Invoke-LabCommand` on DC, same pattern as existing PostInstall steps; no RSAT install required on the Hyper-V host
- **System.Windows.Threading.DispatcherTimer (existing)** — extend the existing 5-second `$script:VMPollTimer`; add a second 60-second enrichment timer for slow metric collection; no new WPF infrastructure needed

**Guest-VM-only dependencies (PowerSTIG 4.28.0 exact-version chain):** PSDscResources 2.12.0, AccessControlDsc 1.4.3, AuditPolicyDsc 1.4.0, AuditSystemDsc 1.1.0, CertificateDsc 5.0.0, ComputerManagementDsc 8.4.0, FileContentDsc 1.3.0.151, GPRegistryPolicyDsc 1.3.1, SecurityPolicyDsc 2.10.0, WindowsDefenderDsc 2.2.0. Only the 10 Windows Server OS STIG dependencies apply; SQL Server, VMware, IIS, DNS Server, and Linux-specific deps are excluded.

See `.planning/research/STACK.md` for full installation scripts and version compatibility table.

### Expected Features

The v1.6 feature set covers four areas. Dashboard enrichment and TTL offer the highest value-to-cost ratio; PowerSTIG STIG baselines deliver the highest overall value but at the highest implementation cost.

**Must have — P1 (v1.6 launch):**
- Lab TTL config block in `Lab-Config.ps1` with `IdleMinutes`, `WallClockHours`, `Action` (Save/Stop)
- `Invoke-LabTTLMonitor` — scheduled task payload that checks TTL and calls `Suspend-VM` or `Stop-VM`
- `Invoke-LabTTLTouch` (snooze) — operator command to reset the TTL countdown
- TTL task cleanup on lab teardown — `Unregister-ScheduledTask` leaves no host noise
- `Invoke-LabADMXImport` — post-DC-promotion step copying OS ADMX templates to Central Store
- `Invoke-LabSTIGBaseline` — role-aware DSC push (`OsRole:'DC'` for domain controllers, `OsRole:'MS'` for member servers) for Windows Server 2019/2022; push mode only (no pull server)
- `StigExceptions` block in `Lab-Config.ps1` — per-VM `SkipRule` overrides to keep labs functional under STIG enforcement
- Dashboard: snapshot age, disk usage, and uptime enrichment fields on VM cards (low cost, high value)
- Dashboard: compliance status column with cached `Test-DscConfiguration` result and last-checked timestamp

**Should have — P2 (after v1.6 core is stable):**
- Third-party ADMX auto-import (MSSecurityBaseline, LAPS, Chrome) — high value, high complexity; needs dedicated phase research
- Compliance result written to run artifact JSON for audit trail
- TTL notification banner or event log entry when auto-suspend fires

**Defer to v2+:**
- Offline/vendored ADMX cache — defer until airgap lab use case is confirmed with actual operators
- Compliance history dashboard — requires run artifact schema changes and reporting infrastructure
- PowerSTIG for SQL Server / IIS roles — validate Windows OS STIG demand first

**Anti-features (do not implement):**
- DSC Pull Server — massive infrastructure overhead for a single-host lab; push mode is sufficient
- Auto-remediate compliance drift continuously — risks breaking running workloads; apply once at deploy time
- TTL-based auto-teardown (destroy VMs) — irreversible data loss; auto-suspend only
- Live compliance polling in dashboard (sub-minute) — `Test-DscConfiguration` is 10–60 seconds per VM; use cached results

See `.planning/research/FEATURES.md` for full dependency graph and prioritization matrix.

### Architecture Approach

All four v1.6 features follow three established architectural patterns: (1) Gated Feature Blocks — all new features opt in via `Enabled = $false` in `$GlobalLabConfig`, preserving existing behavior when flags are absent; (2) Cache-on-Write for Expensive State — STIG compliance is written at apply time to `.planning/stig-compliance.json` and read cheaply by the dashboard poll loop, avoiding live DSC queries on the UI hot path; (3) Task-as-Monitor for Background Automation — the TTL monitor uses Windows Scheduled Tasks rather than background jobs so it survives PowerShell session termination.

**New components by feature:**

| Component | Type | Location |
|-----------|------|----------|
| `Get-LabTTLConfig`, `Test-LabTTLExpired`, `Invoke-LabTTLAction`, `Invoke-LabTTLMonitor` | NEW private helpers | `Private/` |
| `Register-LabTTLTask`, `Unregister-LabTTLTask` | NEW public cmdlets | `Public/` |
| `Get-LabSTIGConfig`, `Invoke-LabApplySTIG` | NEW private helpers | `Private/` |
| `Invoke-LabADMXImport` | NEW private helper | `Private/` |
| `Get-LabEnrichedStatus` | NEW private helper | `Private/` |
| `Get-LabStatus -Enriched` switch | MODIFIED, backward-compat | `Public/Get-LabStatus.ps1` |
| `Lab-Config.ps1` — TTL, STIG, ADMX config blocks | MODIFIED | `Lab-Config.ps1` |
| DC.ps1 PostInstall — STIG + ADMX steps | MODIFIED, gated by Enabled flags | `LabBuilder/Roles/DC.ps1` |
| `VMCard.xaml`, `DashboardView.xaml`, `Update-VMCard` | MODIFIED | `GUI/` |
| `.planning/stig-compliance.json` | NEW data store | `.planning/` |

The GUI uses a two-timer pattern: the existing 5-second `DispatcherTimer` handles the fast VM state heartbeat unchanged; a new 60-second `EnrichmentTimer` collects slow metrics (disk, snapshots, compliance) via a background runspace pushing to a synchronized hashtable, and updates only the enriched `TextBlock` controls. This prevents slow Hyper-V I/O from blocking the WPF UI thread.

See `.planning/research/ARCHITECTURE.md` for full component diagrams, data flow sequences, and documented anti-patterns.

### Critical Pitfalls

Eleven pitfalls were documented across the four feature areas. The most impactful are:

1. **DSC module scope — CurrentUser vs. SYSTEM** — `Install-Module PowerSTIG -Scope CurrentUser` silently fails under DSC because SYSTEM cannot see user-profile modules. Always install without `-Scope` (defaults to machine scope at `C:\Program Files\WindowsPowerShell\Modules`). Add a `Test-PowerStigInstallation` pre-flight guard before attempting MOF compilation. Phase: DSC Baselines.

2. **WinRM MaxEnvelopeSizekb blocking large MOF delivery** — PowerSTIG MOFs routinely exceed WinRM's default 500 KB envelope limit. Add a `Set-LabVMWinRMForDsc` pre-flight step that sets `MaxEnvelopeSizekb = 8192` on each target VM before any `Start-DscConfiguration` call. Phase: DSC Baselines.

3. **ADMX import before AD Web Services is ready** — `Wait-LabVMReady` checks WinRM responsiveness, not ADWS. ADWS can take 60–120 seconds after DC promotion reboot before accepting GPO cmdlets. Implement a `Wait-LabADReady` helper gating on `Get-ADDomain` success. Phase: ADMX/GPO Import.

4. **Scheduled task working directory and path assumptions** — tasks run under SYSTEM with `$PSScriptRoot` potentially unset or pointing to `C:\Windows\System32`. Always register tasks with explicit `-WorkingDirectory` set to the project root; use absolute paths derived from `$GlobalLabConfig.Paths.LabRoot` inside monitor scripts. Phase: Lab TTL.

5. **DispatcherTimer UI freeze from enriched data collection** — adding `Get-VHD`, `Get-VMCheckpoint`, etc. directly to the 5-second DispatcherTimer tick blocks the WPF UI thread for 1–3 seconds per poll with 4+ VMs. The background runspace/synchronized-hashtable pattern must be designed at phase start — retrofitting it after the fact is expensive. Phase: Dashboard Enrichment.

Additional documented pitfalls: PowerSTIG/STIG version mismatch (resolve `StigVersion` at runtime from installed module's `StigData\Processed\` directory, never hard-code); DSC LCM pending configuration state (always use `-Force` on `Start-DscConfiguration` + pre-check LCM state); scheduled task re-registration errors (`-Force` alone is insufficient; use unregister-then-register pattern); missing `$GlobalLabConfig` TTL keys under `Set-StrictMode` (guard all new config key reads with `ContainsKey`); ADMX central store version conflicts (single-source ADMX copy from DC's own `C:\Windows\PolicyDefinitions`); PowerSTIG multi-STIG MOF conflict on DC nodes (apply STIG types sequentially in separate MOF files, not combined in one config block).

See `.planning/research/PITFALLS.md` for full detail, warning signs, and recovery strategies for all eleven pitfalls.

## Implications for Roadmap

The dependency graph and complexity distribution strongly support a four-phase structure. All phases can be developed independently due to `Enabled` flag gating, but the ordering below respects production data dependencies and reduces risk from the highest-complexity items.

### Phase 1: Lab TTL / Lifecycle Monitoring

**Rationale:** Most self-contained feature — no dependency on STIG, ADMX, or dashboard enrichment. Establishes the `$GlobalLabConfig` config block pattern (TTL block) that Phases 2 and 3 replicate. Proving the scheduled task infrastructure in isolation prevents contamination of later, more complex phases.

**Delivers:** Automatic lab suspension (Save or Stop) after configurable idle or wall-clock TTL. Operator snooze command. Clean task teardown on lab removal.

**Addresses:** TTL config block, `Invoke-LabTTLMonitor`, `Invoke-LabTTLTouch`, TTL task cleanup on teardown (all P1 features).

**Pitfalls to address in this phase:** Scheduled task working directory / SYSTEM context (Pitfall 7); scheduled task re-registration idempotency (Pitfall 8); missing `$GlobalLabConfig` TTL keys under `Set-StrictMode` (Pitfall 9).

**Research flag:** Standard patterns — `Register-ScheduledTask` is well-documented. No phase research needed.

### Phase 2: PowerSTIG DSC Baselines

**Rationale:** Highest implementation complexity of the four features. Must come before Dashboard Enrichment because `Invoke-LabApplySTIG` writes `.planning/stig-compliance.json` which the dashboard reads. Builds on the proven `DSCPullServer.ps1` gallery-install-on-target pattern. Placing it second (after Phase 1 establishes the config block pattern) enables clean replication for the STIG config block.

**Delivers:** Role-aware DISA STIG DSC baselines applied at deploy time for Windows Server 2019/2022 DC and member server roles. Per-VM `StigExceptions` overrides. Compliance result cache file at `.planning/stig-compliance.json` for dashboard consumption.

**Addresses:** `Invoke-LabSTIGBaseline` (push mode, DC + MS roles), `StigExceptions` block in `Lab-Config.ps1`, DC.ps1 PostInstall step 3, compliance cache file (all P1 features).

**Stack elements:** PowerSTIG 4.28.0 + 10-module dependency chain installed on guest VMs; DSC v1.1 (PS 5.1 built-in); push mode only.

**Pitfalls to address in this phase:** DSC module scope — CurrentUser vs. SYSTEM (Pitfall 1); STIG version mismatch / runtime version discovery (Pitfall 2); WinRM MaxEnvelopeSizekb pre-flight (Pitfall 3); LCM pending configuration state (Pitfall 4); multi-STIG MOF conflict on DC nodes (Pitfall 11); SkipRule + SkipRuleType incompatibility (Pitfall 11).

**Research flag:** NEEDS phase research — PowerSTIG `OsVersion` string values for 2019/2022 must be confirmed against the installed module's `StigData\Processed\` directory (wiki documents only 2012R2/2016). OrgSettings override file structure needs validation before implementing the `StigExceptions` config block schema.

### Phase 3: ADMX / GPO Auto-Import

**Rationale:** Depends on the DC PostInstall pattern established in Phase 2. ADMX import and optional baseline GPO creation are simpler than STIG (no DSC, no gallery dependencies) but share the same DC-readiness gate requirement. Both Phases 2 and 3 modify `DC.ps1 PostInstall` (steps 3 and 4 respectively) — implementing them in sequence is cleaner than interleaving across separate development cycles.

**Delivers:** ADMX Central Store populated from DC's own `C:\Windows\PolicyDefinitions` after DC promotion. Optional baseline GPO created and linked to domain root.

**Addresses:** `Invoke-LabADMXImport`, `ADMX` config block, DC.ps1 PostInstall step 4, optional `CreateBaselineGPO` (all P1 features).

**Stack elements:** GroupPolicy module (built-in on DC); `Copy-Item` over UNC to SYSVOL path; `Invoke-LabCommand` for GPO cmdlets on DC.

**Pitfalls to address in this phase:** ADMX import before DC/AD is ready — `Wait-LabADReady` helper gating on `Get-ADDomain` (Pitfall 5); ADMX central store version conflicts — single-source copy from DC's `C:\Windows\PolicyDefinitions` (Pitfall 6).

**Research flag:** Standard patterns — well-documented. No phase research needed. Note: if third-party ADMX support (MSSecurityBaseline, LAPS) is added as a P2 follow-on, that sub-feature should trigger a dedicated research step at that time.

### Phase 4: Operational Dashboard Enrichment

**Rationale:** Must come last — consumes `.planning/stig-compliance.json` from Phase 2 and displays TTL-adjacent uptime context from Phase 1. Snapshot age, disk, and uptime fields are available without Phases 1–3, but the compliance column is meaningless without Phase 2 having been applied to at least one VM. The background runspace / synchronized hashtable pattern is the primary design risk and must be established at phase start before any UI code is written.

**Delivers:** VM cards enriched with snapshot count, oldest snapshot age, disk used (GB), uptime, and STIG compliance status (cached, with last-checked timestamp). Two-timer GUI architecture with 5-second heartbeat (unchanged) and 60-second enrichment cycle (new).

**Addresses:** `Get-LabEnrichedStatus`, `Get-LabStatus -Enriched`, `VMCard.xaml` additions, `DashboardView.xaml` additions, `Update-VMCard` enriched field rendering, second `EnrichmentTimer` in `Start-OpenCodeLabGUI.ps1` (all P1 features).

**Pitfalls to address in this phase:** DispatcherTimer UI freeze — background runspace + synchronized hashtable from day one, not retrofitted (Pitfall 10); compliance column showing static "unknown" — display "Applying baseline..." state during DSC apply to avoid operator confusion.

**Research flag:** Standard patterns — WPF DispatcherTimer and runspace patterns are documented in the existing codebase at `Start-OpenCodeLabGUI.ps1:794`. Pattern is proven; implementation is extension, not invention.

### Phase Ordering Rationale

- **Config block pattern dependency:** Phase 1 establishes the `$GlobalLabConfig.TTL` block pattern; Phases 2 and 3 replicate it for `STIG` and `ADMX`. Proving the pattern in Phase 1 before the more complex phases depend on it reduces rework.
- **Compliance cache dependency:** The dashboard compliance column reads `.planning/stig-compliance.json` written by Phase 2. Phase 4 must come after Phase 2 for this column to be meaningful.
- **PostInstall sequence:** Both Phases 2 and 3 modify `DC.ps1 PostInstall`. Implementing them in sequence (Phase 2 adds step 3, Phase 3 adds step 4) is cleaner than interlacing them across separate development cycles.
- **Complexity isolation:** The highest-risk pitfalls (DSC module scope, WinRM envelope size, LCM state) are all in Phase 2. Addressing them in a dedicated phase prevents their risk from contaminating Phase 3 and Phase 4.
- **Dashboard last:** Enrichment is the most visible feature to operators but the most dependent on other features. Shipping it last ensures all data sources (compliance cache, TTL uptime, snapshot state) are available and tested before UI work begins.

### Research Flags

Phases needing deeper research during planning:
- **Phase 2 (DSC Baselines):** PowerSTIG `OsVersion` string values for 2019/2022 must be confirmed by inspecting the installed module (wiki documents only 2012R2/2016). OrgSettings override file structure and the SkipRule exception mechanism need hands-on validation before finalizing the `StigExceptions` config block schema.

Phases with standard patterns (skip research-phase):
- **Phase 1 (TTL / Scheduled Tasks):** `Register-ScheduledTask` API is fully documented. Primary risks are implementation gotchas (working directory, idempotency), not unknown domain.
- **Phase 3 (ADMX/GPO Import):** `Copy-Item` over UNC and GroupPolicy module cmdlets are well-documented. Third-party ADMX is explicitly deferred.
- **Phase 4 (Dashboard Enrichment):** WPF two-timer + runspace pattern is confirmed in the existing codebase at `GUI/Start-OpenCodeLabGUI.ps1:794`. Implementation is extension of a proven pattern.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All core technologies verified against official Microsoft docs, PSGallery listings, and project codebase. PS 5.1 constraint is firm. PowerSTIG 4.28.0 dependency chain verified directly from PSGallery. |
| Features | MEDIUM-HIGH | Table stakes and P1 features are well-defined with clear dependency graph. Third-party ADMX support (P2) is high-value but complexity is underspecified. PowerSTIG OsVersion string format for 2019/2022 is a confirmed gap. |
| Architecture | HIGH | Integration patterns confirmed against existing codebase (first-party reads). Two-timer GUI pattern confirmed against `Start-OpenCodeLabGUI.ps1:794`. PostInstall hook pattern confirmed against `DSCPullServer.ps1`. All architectural decisions are additive; no breaking changes to existing behavior. |
| Pitfalls | HIGH (architecture/scheduling) / MEDIUM (PowerSTIG-specific) | Architecture and scheduling pitfalls confirmed from codebase analysis and official Microsoft docs. PowerSTIG-specific pitfalls (multi-STIG MOF conflict, SkipRule incompatibility) sourced from GitHub issues — specific issue references provided but community-sourced. |

**Overall confidence:** HIGH for Phases 1, 3, 4. MEDIUM-HIGH for Phase 2 (PowerSTIG OsVersion gap pending validation).

### Gaps to Address

- **PowerSTIG OsVersion string format for Windows Server 2019/2022:** The official PowerSTIG wiki documents only `'2012R2'` and `'2016'`. PSGallery 4.22.0+ adds 2019/2022 support but the exact string values must be confirmed by inspecting the installed module's `StigData\Processed\` directory at the start of Phase 2. Implement the runtime version discovery helper (`Get-LabAvailableStigVersions`) before any DSC configuration scaffold is written.

- **OrgSettings exception mechanism validation:** The plan calls for a `StigExceptions` block in `Lab-Config.ps1` exposing PowerSTIG's `SkipRule` and `OrgSettings` parameters. The `SkipRule` + `SkipRuleType` incompatibility (GitHub issue #653) means only one mechanism can be used per resource block. Validate which mechanism better supports the lab use case (disabling smartcard logon, preserving RDP/WinRM accessibility) before finalizing the config block schema in Phase 2.

- **Third-party ADMX bundle approach (P2 decision point):** MSSecurityBaseline, LAPS, and Chrome ADMX packages require either shipping a vendored bundle or downloading from Microsoft at deploy time. This is explicitly deferred from v1.6, but the decision (vendored vs. download-and-cache) should be made before the P2 follow-on phase to avoid requiring schema changes to the `ADMX` config block after it ships.

## Sources

### Primary (HIGH confidence)
- [PowerShell Gallery — PowerSTIG 4.28.0](https://www.powershellgallery.com/packages/PowerSTIG/4.28.0) — dependency list and PS minimum version verified directly
- [microsoft/PowerStig Wiki — WindowsServer](https://github.com/microsoft/PowerStig/wiki/WindowsServer) — OsRole/OsVersion parameters
- [microsoft/PowerStig Wiki — DscGettingStarted](https://github.com/microsoft/PowerStig/wiki/DscGettingStarted) — module scope requirement, WinRM MaxEnvelopeSizekb
- [Microsoft Learn — Register-ScheduledTask](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps) — scheduled task API
- [Microsoft Learn — GroupPolicy Module (WS2025)](https://learn.microsoft.com/en-us/powershell/module/grouppolicy/?view=windowsserver2025-ps) — GPO cmdlets available on DC
- [Microsoft Learn — Create and Manage Central Store](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store) — ADMX Central Store UNC path, copy procedure, version conflict cause
- [Microsoft Learn — Troubleshooting DSC](https://learn.microsoft.com/en-us/powershell/dsc/troubleshooting/troubleshooting?view=dsc-1.1) — LCM pending state, WmiPrvSE cache, DSC event logs
- [Microsoft Learn — Suspend-VM](https://learn.microsoft.com/en-us/powershell/module/hyper-v/suspend-vm?view=windowsserver2025-ps) — Save State action for TTL
- [Microsoft Learn — Test-DscConfiguration](https://learn.microsoft.com/en-us/powershell/module/psdesiredstateconfiguration/test-dscconfiguration?view=dsc-1.1) — compliance check latency characteristics
- Project codebase `GUI/Start-OpenCodeLabGUI.ps1:794` — existing DispatcherTimer pattern for two-timer approach
- Project codebase `LabBuilder/Roles/DSCPullServer.ps1` — proven gallery-install-on-target pattern for PowerSTIG
- Project codebase `Private/Get-LabSnapshotInventory.ps1` — snapshot data shape for enriched status

### Secondary (MEDIUM confidence)
- [microsoft/PowerStig GitHub issue #653](https://github.com/microsoft/PowerStig/issues/653) — SkipRule + SkipRuleType incompatibility
- [PowerShell and WPF: Writing Data from a Different Runspace](https://learn-powershell.net/2012/10/14/powershell-and-wpf-writing-data-to-a-ui-from-a-different-runspace/) — synchronized hashtable pattern for background runspace + WPF
- [Troubleshooting PowerShell Based Scheduled Tasks — ramblingcookiemonster.github.io](http://ramblingcookiemonster.github.io/Task-Scheduler/) — working directory and SYSTEM context pitfalls
- [ADMX templates via PowerShell — woshub.com](https://woshub.com/install-update-group-policy-administrative-templates-admx/) — ADMX copy automation patterns
- [Azure DevTest Labs Auto-Shutdown Policy](https://learn.microsoft.com/en-us/azure/devtest-labs/devtest-lab-auto-shutdown) — TTL pattern reference (cloud product; idle/wall-clock pattern applies locally)
- [Microsoft Learn — Optimizing Performance: Data Binding](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/optimizing-performance-data-binding) — WPF data binding performance for enrichment timer design

---
*Research completed: 2026-02-20*
*Ready for roadmap: yes*
