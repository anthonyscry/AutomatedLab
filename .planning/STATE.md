# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-16)

**Core value:** Every button, menu option, and CLI action works reliably from start to finish — bootstrap through teardown, in both GUI and CLI, on a single host or coordinated across multiple hosts.
**Current focus:** Phase 6: Multi-Host Coordination

## Current Position

Phase: 6 of 6 (Multi-Host Coordination)
Plan: 4 of 5 in current phase
Status: Executing plans
Last activity: 2026-02-17 — Phase 6 Plan 04 complete (SSH transient failure classification and enhanced error messages)

Progress: [█████████░] 88%

## Performance Metrics

**Velocity:**
- Total plans completed: 18
- Average duration: 3.8 min
- Total execution time: 1.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cleanup-config-foundation | 4 | 13.1 min | 3.3 min |
| 02-security-hardening | 3 | 10.4 min | 3.5 min |
| 03-core-lifecycle-integration | 4 | 22.3 min | 5.6 min |
| 05-gui-integration | 4 | 12.2 min | 3.1 min |
| 06-multi-host-coordination | 4 | 10.5 min | 2.6 min |

**Recent Trend:**
- Last 5 plans: 06-04 (3.1 min), 06-03 (3.1 min), 06-02 (3.2 min), 06-01 (1.1 min), 05-04 (1.2 min)
- Trend: Stable

**Plan Details:**
| Plan | Duration | Tasks | Files Changed |
|------|----------|-------|---------------|
| Phase 06-04 | 3.1 min | 5 tasks | 4 files |
| Phase 06-03 | 3.1 min | 4 tasks | 3 files |
| Phase 06-02 | 3.2 min | 4 tasks | 4 files |
| Phase 06-01 | 1.1 min | 1 task | 2 files |
| Phase 05-04 | 1.2 min | 1 task | 1 file |

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
- [Phase 05-01]: Timer lifecycle managed in Switch-View for clean resource cleanup and WPF dispatcher safety
- [Phase 05-02]: Log buffer capped at 2000 entries with FIFO trimming, Application.Current.FindResource for theme-safe color resolution, network settings and admin username persist to both config.json and gui-settings.json
- [Phase 05-03]: Template error display uses inline TextBlock instead of MessageBox, VM names validated client-side, script path unified to OpenCodeLab-App.ps1 for preview and execution consistency
- [Phase 06-01]: Use case-insensitive HashSet for duplicate name detection
- [Phase 06-01]: Default connection to 'local' when missing for safety
- [Phase 06-01]: Normalize connection type to lowercase for consistency
- [Phase 06-02]: Input validation throws immediately on empty/whitespace-only target hosts
- [Phase 06-02]: Config hashtable as third precedence source (parameter > env > config > default)
- [Phase 06-02]: PowerShell parameter binding rejects empty arrays before custom validation runs
- [Phase 06-04]: SSH transient patterns integrated with WinRM patterns in single classifier
- [Phase 06-04]: SSH connection failures (connection refused, no route to host) classified as transient and retried
- [Phase 06-04]: SSH auth failures (host key verification, permission denied) classified as non-transient and not retried

### Pending Todos

- Phase 5 complete (4 plans, 47 GUI tests)
- Next: Phase 6 (Multi-Host Coordination) — FINAL PHASE

### Blockers/Concerns

**From codebase analysis:**
- Large orchestration scripts (OpenCodeLab-App.ps1 1971 lines, Deploy.ps1 1242 lines) — refactoring blocked until error handling tested
- ~~Dual config system (hashtable + legacy variables)~~ — RESOLVED in 01-03 (migrated to $GlobalLabConfig exclusively)
- ~~Three different helper sourcing patterns~~ — RESOLVED in 01-02 (standardized to Lab-Common.ps1 with fail-fast)
- ~~String interpolation bugs in Deploy.ps1/Bootstrap.ps1~~ — RESOLVED in 03-01 (all nested properties wrapped in subexpressions, Pester test validates)

## Session Continuity

Last session: 2026-02-17
Stopped at: Completed 06-04-PLAN.md
Resume file: None
