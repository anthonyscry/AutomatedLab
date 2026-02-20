---
phase: 19-run-history-tracking
plan: 02
subsystem: testing
tags: [powershell, pester, run-history, artifacts, test-coverage]

# Dependency graph
requires:
  - phase: 19-run-history-tracking/19-01
    provides: Get-LabRunHistory public cmdlet and Private helpers Get-LabRunArtifactPaths + Get-LabRunArtifactSummary
provides:
  - Pester 5 test suite for Get-LabRunHistory with 10 tests covering list mode, detail mode, sorting, filtering, and error handling
affects: [future reporting phases, regression suite]

# Tech tracking
tech-stack:
  added: []
  patterns: [TestDrive-style temp-dir tests with try/finally cleanup, New-TestRunArtifact helper for artifact fixture creation, DateTime-vs-string resilient assertions for ConvertFrom-Json coercion]

key-files:
  created:
    - Tests/LabRunHistory.Tests.ps1
  modified: []

key-decisions:
  - "Used $HostName/$UserName parameter names in test helper to avoid collision with PowerShell automatic variable $Host"
  - "EndedUtc sorting test asserts on RunId order rather than exact timestamp string, since ConvertFrom-Json coerces ISO dates to DateTime objects in PS 7"
  - "Detail mode ended_utc assertion uses DateTime type-check to handle PS 7 date coercion gracefully"

patterns-established:
  - "New-TestRunArtifact helper pattern: creates realistic JSON artifacts in a temp directory for isolation"
  - "Avoid PS automatic variable names ($Host, $Error, $Input) in helper function parameters"
  - "Date field assertions should account for ConvertFrom-Json DateTime coercion when comparing string values"

requirements-completed: [HIST-01, HIST-02, HIST-03]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 19 Plan 02: Run History Tracking Tests Summary

**10 Pester 5 tests proving Get-LabRunHistory list mode, detail mode, newest-first sorting, -Last filtering, corrupt-file resilience, and empty-directory handling**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-02-20T22:34:10Z
- **Completed:** 2026-02-20T22:36:43Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Created `Tests/LabRunHistory.Tests.ps1` with 10 passing Pester 5 tests (294 lines)
- Tests dot-source both `Public/Get-LabRunHistory.ps1` and `Private/Get-LabRunArtifactSummary.ps1`
- `New-TestRunArtifact` helper creates realistic OpenCodeLab-Run-{RunId}.json artifacts in temp directories
- List mode tests: empty directory, expected properties, newest-first sort, -Last filter, .txt skip
- Detail mode tests: full data return, all HIST-01 required fields present, throws on missing RunId
- Error handling tests: corrupt JSON skipped with Write-Warning, nonexistent LogRoot returns empty array
- Auto-fixed parameter naming collision (`$Host` -> `$HostName`) and DateTime assertion robustness

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Pester tests for Get-LabRunHistory** - `f6e461f` (test)

## Files Created/Modified

- `Tests/LabRunHistory.Tests.ps1` - 10 Pester 5 tests covering all HIST-01/02/03 behaviors; BeforeAll dot-sources cmdlet + helper, try/finally cleanup, fixture helper creates realistic JSON artifacts

## Decisions Made

- Used `$HostName` and `$UserName` parameter names in `New-TestRunArtifact` to avoid collision with the PowerShell automatic variable `$Host` (which is read-only and cannot be overwritten).
- EndedUtc sort-order test asserts RunId ordering rather than exact timestamp strings, because `ConvertFrom-Json` in PS 7 coerces ISO 8601 date strings to `[datetime]` objects which serialize to locale-dependent format.
- Detail mode `ended_utc` assertion uses a type-check branch: if the value is `[datetime]`, validate Year/Month/Day; otherwise match the year as string.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed reserved PowerShell variable name collision in test helper**
- **Found during:** Task 1 (initial test run)
- **Issue:** `New-TestRunArtifact` used `[string]$Host` parameter, triggering `SessionStateUnauthorizedAccessException` because `$Host` is a read-only automatic variable in PowerShell
- **Fix:** Renamed parameter to `$HostName` (and `$User` to `$UserName` for consistency); updated payload construction accordingly
- **Files modified:** Tests/LabRunHistory.Tests.ps1
- **Verification:** All tests re-run and passed after fix
- **Committed in:** f6e461f (Task 1 commit)

**2. [Rule 1 - Bug] Fixed date assertion brittleness from ConvertFrom-Json DateTime coercion**
- **Found during:** Task 1 (second test run after fix 1)
- **Issue:** `ConvertFrom-Json` in PS 7 converts ISO 8601 strings to `[datetime]` objects; `[string]` cast produces locale-formatted output (`01/03/2026 10:00:00`) not ISO format, breaking exact-match assertions
- **Fix:** Sort-order test asserts on `RunId` order (not EndedUtc string); detail mode test uses type-check branch to validate DateTime year/month/day or string contains year
- **Files modified:** Tests/LabRunHistory.Tests.ps1
- **Verification:** All 10 tests pass with 0 failures
- **Committed in:** f6e461f (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - Bug)
**Impact on plan:** Both fixes necessary for tests to pass. No scope creep — all fixes within the test file only.

## Issues Encountered

None beyond the auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three HIST requirements (HIST-01, HIST-02, HIST-03) now have automated test coverage
- `Tests/LabRunHistory.Tests.ps1` is ready to add to CI regression suite
- Ready to proceed to Phase 20 (Lab Health Reports)

---
*Phase: 19-run-history-tracking*
*Completed: 2026-02-20*
