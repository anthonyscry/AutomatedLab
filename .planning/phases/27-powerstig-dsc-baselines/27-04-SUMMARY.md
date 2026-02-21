---
phase: 27-powerstig-dsc-baselines
plan: 04
subsystem: infra
tags: [powerstig, dsc, stig, compliance, public-cmdlets, postinstall, pester, tdd]

# Dependency graph
requires:
  - phase: 27-powerstig-dsc-baselines
    provides: Invoke-LabSTIGBaselineCore, Write-LabSTIGCompliance, Get-LabSTIGConfig from plans 01-03
provides:
  - Invoke-LabSTIGBaseline: public on-demand STIG re-apply cmdlet (thin wrapper to Core)
  - Get-LabSTIGCompliance: public compliance query cmdlet (reads stig-compliance.json)
  - DC.ps1 PostInstall integration: automatic STIG after AD DS validation, gated on config
  - Build-LabFromSelection.ps1 Phase 11.5: member server STIG after all role PostInstalls
affects:
  - 29 (dashboard uses Get-LabSTIGCompliance to display STIG status from cache)
  - Lab-Common.ps1 auto-discovers Invoke-LabSTIGBaselineCore from Private/

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Public wrapper delegates to Private Core function — avoids naming collision, keeps thin public API"
    - "PostInstall STIG uses inner try-catch inside outer try — STIG failure never aborts DC deployment"
    - "Build-LabFromSelection Phase 11.5 targets non-DC Windows VMs after all role PostInstalls"
    - "ContainsKey guards on GlobalLabConfig.STIG.Enabled + AutoApplyOnDeploy — StrictMode safe"

key-files:
  created:
    - Private/Invoke-LabSTIGBaselineCore.ps1
    - Public/Invoke-LabSTIGBaseline.ps1
    - Public/Get-LabSTIGCompliance.ps1
    - Tests/LabSTIGBaselinePublic.Tests.ps1
    - Tests/LabSTIGCompliancePublic.Tests.ps1
  modified:
    - LabBuilder/Roles/DC.ps1
    - LabBuilder/Build-LabFromSelection.ps1
    - Tests/LabSTIGBaseline.Tests.ps1

key-decisions:
  - "Private function renamed to Invoke-LabSTIGBaselineCore to avoid naming collision with public wrapper; old Invoke-LabSTIGBaseline.ps1 retained for backward compat; existing tests updated to use Core"
  - "DC STIG step placed inside DC.ps1 PostInstall with own try-catch — targets DC by name, runs after AD DS validation completes"
  - "Member server STIG placed in Build-LabFromSelection.ps1 Phase 11.5 — one call for all non-DC Windows VMs, cleaner than modifying each role file"
  - "AutoApplyOnDeploy check uses ContainsKey guard with $true default — consistent with Get-LabSTIGConfig pattern"

patterns-established:
  - "Public STIG cmdlets: thin public wrappers with comment-based help delegating to Private Core functions"
  - "PostInstall STIG: gated on Enabled + AutoApplyOnDeploy, failure isolated with inner try-catch"

requirements-completed: [STIG-05, STIG-06]

# Metrics
duration: 4min
completed: 2026-02-21
---

# Phase 27 Plan 04: Public STIG Cmdlets and PostInstall Integration Summary

**Public Invoke-LabSTIGBaseline wrapper delegates to Invoke-LabSTIGBaselineCore; Get-LabSTIGCompliance reads stig-compliance.json cache; DC and member server VMs get automatic STIG via PostInstall hooks gated on STIG.Enabled**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-21T05:01:13Z
- **Completed:** 2026-02-21T05:05:46Z
- **Tasks:** 2
- **Files modified:** 7 (5 created, 2 modified, 1 updated test)

## Accomplishments

- `Public/Invoke-LabSTIGBaseline.ps1`: thin public wrapper with comment-based help; delegates to `Invoke-LabSTIGBaselineCore` via splatted `$params` hashtable so omitting `-VMName` correctly passes no VMName to Core (targets all lab VMs)
- `Public/Get-LabSTIGCompliance.ps1`: reads `.planning/stig-compliance.json` via `Get-LabSTIGConfig.ComplianceCachePath` default; supports `-CachePath` override; returns `@()` on missing/empty/malformed JSON; full comment-based help
- `Private/Invoke-LabSTIGBaselineCore.ps1`: renamed copy of `Invoke-LabSTIGBaseline` private function — avoids naming collision with public wrapper
- `LabBuilder/Roles/DC.ps1`: PostInstall step 3 calls `Invoke-LabSTIGBaselineCore -VMName $dcName` after AD DS validation; gated on `STIG.Enabled` and `AutoApplyOnDeploy`; inner `try-catch` prevents STIG failure from aborting DC deployment
- `LabBuilder/Build-LabFromSelection.ps1`: Phase 11.5 applies STIG to all non-DC Windows VMs after role PostInstalls complete; same guards; failure does not abort build
- 22 new Pester tests + all 97 existing STIG tests passing (119 total across 6 STIG test files)

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Failing tests for public cmdlets** - `e623483` (test)
2. **Task 1 GREEN: Public STIG cmdlets + Core rename** - `dcb97e8` (feat)
3. **Task 2: PostInstall lifecycle integration** - `11f3bfe` (feat)

_Note: TDD tasks included RED (failing tests) then GREEN (implementation) in separate commits._

## Files Created/Modified

- `Private/Invoke-LabSTIGBaselineCore.ps1` - Renamed `Invoke-LabSTIGBaseline` private function; same full implementation, new function name resolves public/private naming collision
- `Public/Invoke-LabSTIGBaseline.ps1` - Public on-demand STIG re-apply cmdlet; thin wrapper with comment-based help; splatted params ensure VMName=omitted works correctly
- `Public/Get-LabSTIGCompliance.ps1` - Public compliance query; reads JSON cache; returns PSCustomObject[] with 7 fields per VM; empty array on all error conditions
- `Tests/LabSTIGBaselinePublic.Tests.ps1` - 11 tests: parameter routing (single VM, multi-VM, no VMName), return value passthrough, PSCustomObject type check, comment-based help (SYNOPSIS/DESCRIPTION/PARAMETER/EXAMPLE), verbose passthrough, STIG disabled no-op
- `Tests/LabSTIGCompliancePublic.Tests.ps1` - 11 tests: missing cache returns @(), valid JSON returns correct fields and values, empty VMs array, malformed JSON graceful, comment-based help, -CachePath override, default path from Get-LabSTIGConfig
- `LabBuilder/Roles/DC.ps1` - Step 3 in PostInstall: STIG apply to DC by name after AD DS validation; gated on Enabled+AutoApplyOnDeploy; inner try-catch
- `LabBuilder/Build-LabFromSelection.ps1` - Phase 11.5: STIG apply to all non-DC Windows VMs; gated on Enabled+AutoApplyOnDeploy; failure non-fatal
- `Tests/LabSTIGBaseline.Tests.ps1` - Updated to load `Invoke-LabSTIGBaselineCore.ps1` (was `Invoke-LabSTIGBaseline.ps1`)

## Decisions Made

- Private function renamed to `Invoke-LabSTIGBaselineCore` to avoid naming collision with the public wrapper — PowerShell function name scope makes it cleanest to have distinct names for public vs. private layers
- `Public/Invoke-LabSTIGBaseline.ps1` uses `$params = @{}; if ($VMName) { $params['VMName'] = $VMName }; Invoke-LabSTIGBaselineCore @params` pattern — ensures omitting `-VMName` passes no VMName argument (not empty array) to Core, triggering the "target all VMs" branch
- Member server STIG placed in `Build-LabFromSelection.ps1` Phase 11.5 instead of each individual role file — single central location covers all current and future member server roles without modifying each one
- DC STIG step uses inner `try-catch` so STIG failure throws only a warning, never propagating to the outer DC PostInstall `catch` block that would surface as a fatal DC failure

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] replace_all overshoot on test file update**
- **Found during:** Task 1 (GREEN phase - renaming LabSTIGBaseline to Core in existing test)
- **Issue:** `replace_all: true` on `Invoke-LabSTIGBaseline` replaced the path reference `Private/Invoke-LabSTIGBaseline.ps1` to `Private/Invoke-LabSTIGBaselineCoreCore.ps1` (double-Core)
- **Fix:** Reverted the path reference to `Private/Invoke-LabSTIGBaselineCore.ps1` via targeted Edit
- **Files modified:** Tests/LabSTIGBaseline.Tests.ps1
- **Verification:** All 20 existing tests pass after fix
- **Committed in:** dcb97e8 (Task 1 GREEN commit)

## Issues Encountered

- None beyond the auto-fixed deviation above

## User Setup Required

None — all new cmdlets are local functions auto-loaded by Lab-Common.ps1. No external services or dependencies needed.

## Next Phase Readiness

- Phase 27 is feature-complete: config -> profile mapping -> pre-flight -> installation -> MOF compile with exceptions -> DSC push -> compliance cache -> public query/re-apply -> PostInstall integration
- All 6 STIG requirements (STIG-01 through STIG-06) are fulfilled across Plans 01-04
- Phase 29 dashboard can call `Get-LabSTIGCompliance` to display per-VM STIG status — schema is stable
- `Lab-Common.ps1` auto-discovers `Invoke-LabSTIGBaselineCore` from `Private/` — no registration needed

## Self-Check: PASSED

- FOUND: Private/Invoke-LabSTIGBaselineCore.ps1
- FOUND: Public/Invoke-LabSTIGBaseline.ps1
- FOUND: Public/Get-LabSTIGCompliance.ps1
- FOUND: Tests/LabSTIGBaselinePublic.Tests.ps1
- FOUND: Tests/LabSTIGCompliancePublic.Tests.ps1
- FOUND: LabBuilder/Roles/DC.ps1 (modified)
- FOUND: LabBuilder/Build-LabFromSelection.ps1 (modified)
- FOUND commit: e623483 (test(27-04): add failing tests for public STIG cmdlets)
- FOUND commit: dcb97e8 (feat(27-04): add public STIG cmdlets and rename private core function)
- FOUND commit: 11f3bfe (feat(27-04): integrate STIG application into PostInstall lifecycle)
- All 97 STIG tests passing (97/97)
- DC.ps1 contains Invoke-LabSTIGBaselineCore, gated on STIG.Enabled + AutoApplyOnDeploy
- Build-LabFromSelection.ps1 Phase 11.5 targets non-DC Windows VMs

---
*Phase: 27-powerstig-dsc-baselines*
*Completed: 2026-02-21*
