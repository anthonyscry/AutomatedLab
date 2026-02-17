# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-16)

**Core value:** Every button, menu option, and CLI action works reliably from start to finish — bootstrap through teardown, in both GUI and CLI, on a single host or coordinated across multiple hosts.
**Current focus:** Phase 5: GUI Integration

## Current Position

Phase: 5 of 6 (GUI Integration)
Plan: 2 of 4 in current phase
Status: Executing
Last activity: 2026-02-17 — Completed 05-01 (CLI-GUI action parity and timer lifecycle)

Progress: [███████░░░] 72%

## Performance Metrics

**Velocity:**
- Total plans completed: 13
- Average duration: 4.3 min
- Total execution time: 0.95 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cleanup-config-foundation | 4 | 13.1 min | 3.3 min |
| 02-security-hardening | 3 | 10.4 min | 3.5 min |
| 03-core-lifecycle-integration | 4 | 22.3 min | 5.6 min |
| 05-gui-integration | 2 | 7.8 min | 3.9 min |

**Recent Trend:**
- Last 5 plans: 05-01 (4.1 min), 05-02 (3.7 min), 03-05 (4.5 min), 03-04 (3.7 min), 03-03 (8.1 min)
- Trend: Stable

**Plan Details:**
| Plan | Duration | Tasks | Files Changed |
|------|----------|-------|---------------|
| Phase 05-01 | 4.1 min | 2 tasks | 2 files |
| Phase 05-02 | 3.7 min | 2 tasks | 2 files |
| Phase 03-05 | 4.5 min | 2 tasks | 2 files |
| Phase 03-04 | 3.7 min | 2 tasks | 2 files |
| Phase 03-03 | 8.1 min | 2 tasks | 16 files |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Brownfield hardening milestone — 107 functions exist but need integration testing and wiring
- Cleanup dead code and archive — reduce repo noise and search pollution
- Include multi-host coordinator — infrastructure exists, user wants it working
- [Phase 01-cleanup-config-foundation]: Standardized helper sourcing: removed redundant $OrchestrationHelperPaths, added fail-fast error handling
- [Phase 01]: Aggressive dead code removal without reference copies
- [Phase 01-cleanup-config-foundation]: Template validation changed from soft errors to immediate throw with shared validation helper
- [Phase 01]: Killed legacy variables immediately without deprecation period (user decision)
- [Phase 01]: Config validation fails loudly on missing/invalid required fields
- [Phase 02-security-hardening]: Enhanced password resolution with warning-on-default and interactive fallback
- [Phase 02-security-hardening]: Use lab-specific persistent known_hosts file instead of /dev/null for real host key verification
- [Phase 02-security-hardening]: Make Git download checksum validation mandatory (reject if no hash configured)
- [Phase 02-security-hardening]: Use multi-layer credential scrubbing (known defaults, env vars, GlobalLabConfig) with simple string replacement
- [Phase 03-01]: Mandatory subexpression syntax for nested config properties - PowerShell does not interpolate "$GlobalLabConfig.X.Y" correctly without $()
- [Phase 03-01]: Remove all legacy variable fallbacks - Phase 01 migration complete, no need for backward compatibility
- [Phase 03-01]: Pester test enforcement of interpolation rules to prevent regression
- [Phase 03-04]: SSH known_hosts cleanup during teardown to prevent host key errors on redeploy
- [Phase 03-04]: NAT removal verification to catch silent failures
- [Phase 03-04]: Confirmation gates on destructive actions respect Force/NonInteractive flags
- [Phase 03-03]: Fixed systemic invalid parameter syntax across 12 files - PowerShell requires simple parameter names in param blocks, not dotted properties like $GlobalLabConfig.Network.NatName (same issue as 03-01 but in additional files discovered during test execution)
- [Phase 03-05]: Complete legacy variable migration - Invoke-BulkAdditionalVMProvision was last function using $Server_Memory, $Client_Memory, $Server_Processors, $Client_Processors instead of $GlobalLabConfig.VMSizing
- [Phase 03-05]: Subexpression syntax enforcement - Fixed 7 string interpolation bugs, added comprehensive action routing tests to prevent regressions
- [Phase 04-01]: Fixed param syntax in FileServer/Client roles, added prereq validation to DHCP/DSC
- [Phase 04-02]: All 6 core Windows roles get try-catch error handling with post-install service verification
- [Phase 04-03]: DC failure is fatal (aborts build), post-install summary table, 15-role scriptMap in orchestrator
- [Phase 04-04]: Linux roles return safe stubs when config missing, LinuxRoleBase validates before property access
- [Phase 05-gui-integration]: Timer lifecycle managed in Switch-View for clean resource cleanup and WPF dispatcher safety

### Pending Todos

- Phase 4 complete (4 plans, 111 tests)
- Next: Phase 5 (GUI Integration)

### Blockers/Concerns

**From codebase analysis:**
- Large orchestration scripts (OpenCodeLab-App.ps1 1971 lines, Deploy.ps1 1242 lines) — refactoring blocked until error handling tested
- ~~Dual config system (hashtable + legacy variables)~~ — RESOLVED in 01-03 (migrated to $GlobalLabConfig exclusively)
- ~~Three different helper sourcing patterns~~ — RESOLVED in 01-02 (standardized to Lab-Common.ps1 with fail-fast)
- ~~String interpolation bugs in Deploy.ps1/Bootstrap.ps1~~ — RESOLVED in 03-01 (all nested properties wrapped in subexpressions, Pester test validates)

## Session Continuity

Last session: 2026-02-17
Stopped at: Completed 05-01-PLAN.md (CLI-GUI action parity and timer lifecycle)
Resume file: None
