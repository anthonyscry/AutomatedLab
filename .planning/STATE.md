# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.
**Current focus:** v1.6 Lab Lifecycle & Security Automation — Phase 29: Dashboard Enrichment

## Current Position

Phase: 29 of 29 (Dashboard Enrichment)
Plan: 5 of 5 (GUI Integration and Final Testing) - COMPLETE
Status: Phase 29 complete
Last activity: 2026-02-21 — GUI timer integration complete, all 28 dashboard tests passing, verification document created

Progress: [██████████] 100% (v1.6 Phase 29)

## Performance Metrics

**v1.0 Brownfield Hardening & Integration:** 6 phases, 25 plans, 56 requirements
**v1.1 Production Robustness:** 4 phases, 13 plans, 19 requirements
**v1.2 Delivery Readiness:** 3 phases, 16 plans, 11 requirements
**v1.3 Lab Scenarios & Operator Tooling:** 4 phases, 8 plans, 14 requirements
**v1.4 Configuration Management & Reporting:** 4 phases, 8 plans, 13 requirements
**v1.5 Advanced Scenarios & Multi-OS:** 4 phases, 8 plans, 16 requirements (~226 new tests)
**v1.6 Lab Lifecycle & Security Automation:** Phase 28 complete (4 plans, 39 tests), Phase 29 complete (5 plans, 28 tests)

## Accumulated Context

### Decisions

Full log in PROJECT.md Key Decisions table. Key decisions for v1.6:
- STIG config block added to GlobalLabConfig after TTL block; Enabled=$false by default
- Get-LabSTIGConfig uses ContainsKey guards matching Phase 26 TTL pattern; Exceptions defaults to @{} not null
- Get-LabSTIGProfile: caller discovers OS version and passes as param — no live VM queries inside helper; StartsWith prefix matching handles full build.revision strings
- Test-PowerStigInstallation: try/catch returns structured PSCustomObject on WinRM failure; Invoke-Command mocked at Pester level for unit tests
- All new features gated by `Enabled = $false` in $GlobalLabConfig — existing behavior unchanged when config keys absent
- STIG compliance uses cache-on-write (.planning/stig-compliance.json) — no live DSC queries on dashboard hot path
- TTL monitoring uses Windows Scheduled Tasks (survives PowerShell session termination), not background jobs
- Dashboard enrichment uses 60-second background runspace + synchronized hashtable — must be designed at phase start, not retrofitted
- DSC modules must install -Scope AllUsers (machine scope) — CurrentUser silently fails under SYSTEM context
- [Phase 27-03]: Side-effect Invoke-Command calls piped to Out-Null — prevents null pipeline leakage from mocks causing PSCustomObject to be wrapped in Object[] array
- [Phase 27-03]: Pester 5: stub missing DSC cmdlets as global: functions in BeforeAll so Pester can mock them on non-Windows test host
- [Phase 27]: Private function renamed to Invoke-LabSTIGBaselineCore to avoid public/private naming collision; Public wrapper uses splatted params to correctly pass no-VMName case
- [Phase 27]: Member server STIG placed in Build-LabFromSelection.ps1 Phase 11.5 — single location covers all current and future member server roles
- [Phase 27-05]: DSC Configuration keyword placed inside here-string evaluated via Invoke-Expression on remote VM — avoids ParseException on Linux/non-DSC test hosts where Configuration keyword is unsupported
- [Phase 27-05]: PowerSTIG exception hashtable uses ValueData='' skip marker pattern; compile+apply in single Invoke-Command -ComputerName session to avoid MOF file transfer
- [Phase 28-01]: ADMX config block added to GlobalLabConfig after STIG block; Enabled=$true by default (ADMX import runs by default)
- [Phase 28-01]: Get-LabADMXConfig uses ContainsKey guards matching Get-LabSTIGConfig pattern; ThirdPartyADMX defaults to @()
- [Phase 28-01]: Comma-prefix operator (,@()) used to prevent PowerShell from unwrapping single-element hashtable arrays in PSCustomObject properties
- [Phase 28-01]: Tests treat null and empty array equivalently due to PowerShell PSCustomObject empty array -> null conversion limitation
- [Phase 28-02]: Wait-LabADReady gates on Get-ADDomain success with 120s default timeout, 10s retry interval
- [Phase 28-02]: Invoke-LabADMXImport copies OS ADMX/ADML from DC PolicyDefinitions to SYSVOL Central Store via Invoke-Command on DC
- [Phase 28-02]: Third-party ADMX bundles processed independently with per-bundle error isolation
- [Phase 28-02]: PowerShell 5.1 compatibility: Where-Object { -not $_.PSIsContainer } instead of -File parameter for Get-ChildItem
- [Phase 28-03]: Four baseline GPO JSON templates created (password, lockout, audit, AppLocker) in Templates/GPO/
- [Phase 28-03]: ConvertTo-DomainDN helper converts FQDN to DN format (DC=domain,DC=tld) for New-GPLink targets
- [Phase 28-03]: Invoke-LabADMXImport extended with GPO creation logic using New-GPO, Set-GPRegistryValue, New-GPLink
- [Phase 28-03]: GPO creation gated by CreateBaselineGPO config flag; templates loaded from <repoRoot>/Templates/GPO/*.json
- [Phase 28-03]: Per-template error isolation; GPOs counted in FilesImported metric
- [Phase 28-04]: ADMX/GPO operations integrated into DC.ps1 PostInstall as step 4 (after STIG step 3)
- [Phase 28-04]: Wait-LabADReady gates ADMX/GPO operations on ADWS readiness with 120s timeout
- [Phase 28-04]: DC PostInstall uses same ContainsKey guard pattern as STIG step; ADMX failure doesn't abort deployment
- [Phase 28-04]: LabDCPostInstall.Tests.ps1 created with 5 integration tests for complete PostInstall flow
- [Phase 28]: Complete Phase 28 implementation with 39 passing tests across 5 test files
- [Phase 29-01]: Dashboard config block added to GlobalLabConfig after ADMX block; SnapshotStaleDays=7, SnapshotStaleCritical=30, DiskUsagePercent=80, DiskUsageCritical=95, UptimeStaleHours=72
- [Phase 29-01]: Get-LabDashboardConfig uses ContainsKey guards matching Get-LabTTLConfig pattern; all values type-cast to [int]
- [Phase 29-01]: Config block ordering established: ADMX -> Dashboard -> SSH for maintainability
- [Phase 29-02]: Get-LabSnapshotAge returns age in days of oldest snapshot or $null when none exist
- [Phase 29-02]: Get-LabVMDiskUsage returns FileSizeGB, SizeGB, UsagePercent with multi-disk support
- [Phase 29-02]: Get-LabVMMetrics orchestrates collection of all 4 metrics (snapshot, disk, uptime, STIG) per VM
- [Phase 29-02]: Global function stubs used for Hyper-V cmdlets (Get-VMSnapshot, Get-VMHardDiskDrive, Get-VHD) for cross-platform testing
- [Phase 29-03]: Background runspace uses synchronized hashtable ($script:DashboardMetrics) for thread-safe data sharing
- [Phase 29-03]: Start-DashboardMetricsRefreshRunspace creates STA runspace with 60-second collection loop
- [Phase 29-03]: Stop-DashboardMetricsRefreshRunspace sets Continue flag to false, waits up to 5s, disposes resources
- [Phase 29-03]: Runsapce lifecycle wired to dashboard view (start on load, stop on window close)
- [Phase 29-03]: VM names captured from GlobalLabConfig.Lab.CoreVMNames or defaults (dc1, svr1, ws1)
- [Phase 29-04]: VMCard.xaml expanded from 5 to 9 rows to accommodate 4 new metric displays
- [Phase 29-04]: Get-StatusBadgeForMetric returns emoji badges (🟢🟡🔴⚪) based on threshold comparison
- [Phase 29-04]: Update-VMCardWithMetrics reads from synchronized hashtable and updates all 4 TextBlocks
- [Phase 29-04]: Metric format: Icon + Label + Value + Status Badge with FontSize 11 for compact display
- [Phase 29-05]: Update-VMCardWithMetrics integrated into Initialize-DashboardView timer (5-second poll) and initial load
- [Phase 29-05]: UI thread reads from synchronized hashtable - no Hyper-V calls on UI thread path
- [Phase 29-05]: LabDashboardMetrics.Tests.ps1 created with 5 integration tests covering end-to-end metrics flow
- [Phase 29]: Background runspace uses synchronized hashtable for thread-safe data sharing between background collector and UI thread
- [Phase 29]: STA apartment state required for WPF compatibility - prevents COM object failures in runspace
- [Phase 29]: Complete Phase 29 implementation with 28 passing tests across 4 test files

### Pending Todos

None

### Blockers/Concerns

None — Phase 29 complete. All 5 requirements verified with 28 passing tests.

## Session Continuity

Last session: 2026-02-21
Stopped at: Completed Plan 29-05 (GUI Integration and Final Testing) - Phase 29 complete
Resume file: None

---
*State initialized: 2026-02-17 for v1.1 milestone*
*Last updated: 2026-02-21 after Phase 29 completion*
*Last updated: 2026-02-21 after Plan 29-04 completion*
