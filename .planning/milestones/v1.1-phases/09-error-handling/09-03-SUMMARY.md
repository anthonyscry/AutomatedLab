---
phase: 09-error-handling
plan: 03
subsystem: error-handling
tags: [powershell, pester, try-catch, error-handling, resolution-functions, menu-functions]

# Dependency graph
requires:
  - phase: 09-02
    provides: error handling pattern for batch 2 functions (established try-catch with throw/Write-Warning convention)
provides:
  - try-catch error handling in 8 resolution/policy functions (Resolve-Lab* functions)
  - try-catch error handling in 6 menu functions (Show-LabMenu, Invoke-Lab*Menu/Wizard functions)
  - ErrorHandling-Batch3.Tests.ps1 with 56 tests verifying pattern for all 14 functions
affects: [09-04-error-handling, 10-diagnostics]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Resolution functions use throw with function-name prefix (resolution failure = wrong operation executed)"
    - "Menu functions use Write-Warning with function-name prefix (menu errors display gracefully, not crash)"
    - "Error message format: 'FunctionName: context message - $_'"

key-files:
  created:
    - Tests/ErrorHandling-Batch3.Tests.ps1
  modified:
    - Private/Resolve-LabActionRequest.ps1
    - Private/Resolve-LabCoordinatorPolicy.ps1
    - Private/Resolve-LabDispatchMode.ps1
    - Private/Resolve-LabDispatchPlan.ps1
    - Private/Resolve-LabModeDecision.ps1
    - Private/Resolve-LabNoExecuteStateOverride.ps1
    - Private/Resolve-LabOperationIntent.ps1
    - Private/Resolve-LabOrchestrationIntent.ps1
    - Private/Show-LabMenu.ps1
    - Private/Invoke-LabInteractiveMenu.ps1
    - Private/Invoke-LabAddVMMenu.ps1
    - Private/Invoke-LabAddVMWizard.ps1
    - Private/Invoke-LabConfigureRoleMenu.ps1
    - Private/Invoke-LabSetupMenu.ps1
    - Tests/OperationIntent.Tests.ps1

key-decisions:
  - "Resolution functions use throw (not Write-Warning) because incorrect resolution executes the wrong operation"
  - "Menu functions use Write-Warning (not throw) so interactive users see readable messages rather than crashing the app"
  - "Existing OperationIntent tests updated: wildcard patterns 'Unsupported mode*' -> '*Unsupported mode*' to match prefixed error messages"

patterns-established:
  - "Batch 3 pattern: Resolution functions use throw, menu functions use Write-Warning"
  - "Test pattern: Context blocks per function with BeforeAll loading file content"

requirements-completed: [ERR-01, ERR-03]

# Metrics
duration: 20min
completed: 2026-02-17
---

# Phase 09 Plan 03: Error Handling Batch 3 Summary

**try-catch error handling added to 14 resolution and menu functions: 8 Resolve-Lab* functions throw on failure, 6 menu functions Write-Warning for graceful degradation; 56 new tests, 837 total passing**

## Performance

- **Duration:** 20 min
- **Started:** 2026-02-17T14:09:48Z
- **Completed:** 2026-02-17T14:29:00Z
- **Tasks:** 3 + 1 auto-fix
- **Files modified:** 15

## Accomplishments

- Added outer try-catch to 8 resolution/policy functions (Resolve-LabActionRequest, Resolve-LabCoordinatorPolicy, Resolve-LabDispatchMode, Resolve-LabDispatchPlan, Resolve-LabModeDecision, Resolve-LabNoExecuteStateOverride, Resolve-LabOperationIntent, Resolve-LabOrchestrationIntent)
- Added outer try-catch to 6 menu functions (Show-LabMenu, Invoke-LabInteractiveMenu, Invoke-LabAddVMMenu, Invoke-LabAddVMWizard, Invoke-LabConfigureRoleMenu, Invoke-LabSetupMenu)
- Created ErrorHandling-Batch3.Tests.ps1 with 56 tests verifying try-catch presence and function-name prefix for all 14 functions
- Full test suite: 837 passing, 0 failed (8 skipped pre-existing)

## Task Commits

1. **Task 1: Add try-catch to resolution functions (8 files)** - `81ff016` (feat)
2. **Task 2: Add try-catch to menu functions (6 files)** - `f1e6d05` (feat)
3. **Task 3: Create ErrorHandling-Batch3.Tests.ps1** - `29cc248` (test)
4. **Auto-fix: Update OperationIntent tests for prefixed messages** - `b133d19` (fix)

**Plan metadata:** _(docs commit follows)_

## Files Created/Modified

- `Private/Resolve-LabActionRequest.ps1` - outer try-catch with throw "Resolve-LabActionRequest: failed to resolve action request - $_"
- `Private/Resolve-LabCoordinatorPolicy.ps1` - outer try-catch wrapping complex policy evaluation logic
- `Private/Resolve-LabDispatchMode.ps1` - outer try-catch wrapping mode resolution
- `Private/Resolve-LabDispatchPlan.ps1` - outer try-catch wrapping dispatch plan switch
- `Private/Resolve-LabModeDecision.ps1` - outer try-catch wrapping mode decision tree
- `Private/Resolve-LabNoExecuteStateOverride.ps1` - outer try-catch wrapping file I/O and JSON parsing
- `Private/Resolve-LabOperationIntent.ps1` - outer try-catch wrapping operation intent resolution
- `Private/Resolve-LabOrchestrationIntent.ps1` - outer try-catch wrapping orchestration intent
- `Private/Show-LabMenu.ps1` - outer try-catch with Write-Warning "Show-LabMenu: failed to display menu - $_"
- `Private/Invoke-LabInteractiveMenu.ps1` - outer try-catch wrapping do-while menu loop
- `Private/Invoke-LabAddVMMenu.ps1` - outer try-catch wrapping VM type selection
- `Private/Invoke-LabAddVMWizard.ps1` - outer try-catch wrapping wizard I/O and VM creation
- `Private/Invoke-LabConfigureRoleMenu.ps1` - outer try-catch wrapping role selection flow
- `Private/Invoke-LabSetupMenu.ps1` - outer try-catch wrapping setup prompts and orchestration
- `Tests/ErrorHandling-Batch3.Tests.ps1` - 56 tests verifying try-catch pattern for all 14 functions
- `Tests/OperationIntent.Tests.ps1` - updated wildcard patterns to match prefixed error messages

## Decisions Made

- Resolution functions use `throw` because a wrong resolution means the wrong operation gets executed - this must be a terminating error
- Menu functions use `Write-Warning` because menu errors should display to the interactive user gracefully rather than crashing the entire app
- OperationIntent.Tests.ps1 needed updating: existing tests used leading-anchor wildcards (`"Unsupported mode*"`) that no longer matched after the try-catch wrapping prefixed the error message; changed to `"*Unsupported mode*"` to match substring

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated OperationIntent tests to match new prefixed error message format**
- **Found during:** Full test suite run after Task 3
- **Issue:** `OperationIntent.Tests.ps1` tested `Should -Throw "Unsupported mode*"` and `Should -Throw "Unsupported action*"` — but our outer try-catch re-throws as `"Resolve-LabOperationIntent: failed to resolve operation intent - Unsupported mode..."`, so the existing patterns failed to match
- **Fix:** Changed patterns to `"*Unsupported mode*"` and `"*Unsupported action*"` (leading wildcard allows substring match)
- **Files modified:** `Tests/OperationIntent.Tests.ps1`
- **Verification:** `Invoke-Pester Tests/OperationIntent.Tests.ps1` — 4/4 pass; full suite 837/837 pass
- **Committed in:** `b133d19`

---

**Total deviations:** 1 auto-fixed ([Rule 1 - Bug])
**Impact on plan:** Required fix for test correctness. No scope creep.

## Issues Encountered

The initial test file used `-ForEach` with `$script:` arrays set in `BeforeAll` — Pester 5 discovers tests at parse time so data must be inline for `-ForEach`. Rewrote as explicit Context blocks per function (standard pattern for this codebase).

## Next Phase Readiness

- Batch 3 complete: 14 resolution/policy/menu functions now have error handling
- Ready for Phase 09-04 (Batch 4: remaining Private functions)
- No blockers

---
*Phase: 09-error-handling*
*Completed: 2026-02-17*

## Self-Check: PASSED

All 16 files verified present. All 4 commits verified in git log.
- `81ff016` feat(09-03): add try-catch to 8 resolution functions
- `f1e6d05` feat(09-03): add try-catch to 6 menu functions
- `29cc248` test(09-03): add ErrorHandling-Batch3.Tests.ps1 for 14 functions
- `b133d19` fix(09-03): update OperationIntent tests to match prefixed error messages
