---
phase: 08-orchestrator-extraction
plan: 01
subsystem: orchestration
tags: [powershell, extraction, refactoring, unit-tests, pester]

# Dependency graph
requires: []
provides:
  - 11 pure utility functions extracted from OpenCodeLab-App.ps1 to Private/ with explicit parameters
  - Convert-LabArgumentArrayToSplat: parses argument arrays into hashtables for splatting
  - Resolve-LabScriptPath: finds repo scripts with explicit ScriptDir parameter
  - Add-LabRunEvent: adds events to run list with explicit RunEvents parameter
  - Invoke-LabRepoScript: invokes repo scripts with explicit ScriptDir and RunEvents
  - Get-LabExpectedVMs: returns expected VMs from LabConfig
  - Get-LabPreflightArgs: returns empty preflight arg array
  - Get-LabBootstrapArgs: builds bootstrap arg array from explicit params
  - Get-LabDeployArgs: builds deploy arg array from explicit params
  - Get-LabHealthArgs: returns empty health arg array
  - Import-LabModule: imports AutomatedLab module and lab with explicit LabName
  - Invoke-LabLogRetention: runs log retention with explicit RetentionDays and LogRoot
  - 46 unit tests for all 11 extracted functions (612 total passing)
affects: [08-02, 08-03, 08-04, phase-09, phase-10]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "[CmdletBinding()] on all extracted helpers"
    - "Explicit parameter injection to replace script-scope variable closure dependencies"
    - "AllowEmptyCollection() for Generic List parameters that start empty"
    - "Lab-prefix naming convention for extracted functions"

key-files:
  created:
    - Private/Convert-LabArgumentArrayToSplat.ps1
    - Private/Resolve-LabScriptPath.ps1
    - Private/Add-LabRunEvent.ps1
    - Private/Invoke-LabRepoScript.ps1
    - Private/Get-LabExpectedVMs.ps1
    - Private/Get-LabPreflightArgs.ps1
    - Private/Get-LabBootstrapArgs.ps1
    - Private/Get-LabDeployArgs.ps1
    - Private/Get-LabHealthArgs.ps1
    - Private/Import-LabModule.ps1
    - Private/Invoke-LabLogRetention.ps1
    - Tests/OrchestratorExtraction-Batch1.Tests.ps1
  modified:
    - OpenCodeLab-App.ps1
    - Tests/DeployModeHandoff.Tests.ps1

key-decisions:
  - "AllowEmptyCollection() required for Generic List parameters in Mandatory binding"
  - "Inline function extraction does not change behavior - all call sites pass script-scope vars explicitly"
  - "Updated DeployModeHandoff tests to check Private/ files instead of App.ps1 inline definitions"

patterns-established:
  - "Extracted helpers use Lab-prefix (Get-LabExpectedVMs not Get-ExpectedVMs)"
  - "Script-scope variable dependencies replaced with explicit parameters at each call site"
  - "RunEvents passed explicitly as List[object] with AllowEmptyCollection()"

requirements-completed:
  - EXT-01
  - EXT-03
  - EXT-04

# Metrics
duration: 16min
completed: 2026-02-17
---

# Phase 8 Plan 01: Orchestrator Extraction Batch 1 Summary

**11 pure utility functions extracted from OpenCodeLab-App.ps1 to Private/ with explicit parameters, eliminating all script-scope closure dependencies, with 46 unit tests and zero regressions in 612-test suite**

## Performance

- **Duration:** 16 min
- **Started:** 2026-02-17T04:06:03Z
- **Completed:** 2026-02-17T04:22:01Z
- **Tasks:** 10
- **Files modified:** 14 (12 created, 2 modified)

## Accomplishments

- Extracted 11 functions with explicit parameters, eliminating script-scope variable closure dependencies
- Reduced OpenCodeLab-App.ps1 from 2,012 to 1,862 lines (-150 lines)
- Created 46 unit tests (all passing) covering all 11 extracted functions
- Full test suite passes: 612 tests, 0 failures (up from 566 before this batch)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract Convert-LabArgumentArrayToSplat** - `3762ffa` (feat)
2. **Task 2: Extract Resolve-LabScriptPath** - `fcc489c` (feat)
3. **Task 3: Extract Add-LabRunEvent** - `ad5de7d` (feat)
4. **Task 4: Extract Invoke-LabRepoScript** - `3b6ed5a` (feat)
5. **Task 5: Extract Get-LabExpectedVMs** - `a5626b1` (feat)
6. **Task 6: Extract 4 arg-builder helpers** - `d6bec69` (feat)
7. **Task 7: Extract Import-LabModule** - `447ca9b` (feat)
8. **Task 8: Extract Invoke-LabLogRetention** - `8f8c7e3` (feat)
9. **Task 9: Unit tests for all 11 functions** - `34de31e` (test)
10. **Task 10: Fix regressions in DeployModeHandoff tests** - `c87eb82` (fix)

## Files Created/Modified

### Created
- `Private/Convert-LabArgumentArrayToSplat.ps1` - Parses -Key Value/switch arg arrays to hashtable
- `Private/Resolve-LabScriptPath.ps1` - Finds repo scripts with explicit ScriptDir param
- `Private/Add-LabRunEvent.ps1` - Adds events to run list; RunEvents as explicit param
- `Private/Invoke-LabRepoScript.ps1` - Invokes repo scripts; ScriptDir+RunEvents explicit
- `Private/Get-LabExpectedVMs.ps1` - Returns CoreVMNames from explicit LabConfig param
- `Private/Get-LabPreflightArgs.ps1` - Returns empty arg array (no deps)
- `Private/Get-LabBootstrapArgs.ps1` - Builds bootstrap args with explicit Mode/NonInteractive/AutoFixSubnetConflict
- `Private/Get-LabDeployArgs.ps1` - Builds deploy args with explicit Mode/NonInteractive/AutoFixSubnetConflict
- `Private/Get-LabHealthArgs.ps1` - Returns empty arg array (no deps)
- `Private/Import-LabModule.ps1` - Imports AutomatedLab module+lab with explicit LabName
- `Private/Invoke-LabLogRetention.ps1` - Log retention with explicit RetentionDays+LogRoot params
- `Tests/OrchestratorExtraction-Batch1.Tests.ps1` - 46 unit tests for all 11 functions

### Modified
- `OpenCodeLab-App.ps1` - Removed 11 inline definitions; updated all call sites with explicit params
- `Tests/DeployModeHandoff.Tests.ps1` - Updated to check Private/ files for extracted functions

## Decisions Made

- **AllowEmptyCollection() for List parameters**: PowerShell's Mandatory binding rejects empty Generic List. Added `[AllowEmptyCollection()]` to `$RunEvents` parameter in Add-LabRunEvent and Invoke-LabRepoScript.
- **Extraction does not change behavior**: All extracted functions produce identical output; only dependency injection pattern changes (explicit params instead of closures).
- **Updated DeployModeHandoff tests**: Tests were checking inline implementations that moved to Private/. Updated to verify correct files.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AllowEmptyCollection() fix for Generic List mandatory binding**
- **Found during:** Task 3 (Add-LabRunEvent)
- **Issue:** `[Parameter(Mandatory)][System.Collections.Generic.List[object]]` rejects empty list (common at start of run)
- **Fix:** Added `[AllowEmptyCollection()]` attribute to RunEvents parameter in Add-LabRunEvent and Invoke-LabRepoScript
- **Files modified:** Private/Add-LabRunEvent.ps1, Private/Invoke-LabRepoScript.ps1
- **Verification:** Test with empty list passes
- **Committed in:** ad5de7d (Task 3 commit)

**2. [Rule 1 - Bug] Fixed scriptblock closure pattern for Invoke-LabRepoScript in menu handlers**
- **Found during:** Task 4 (Invoke-LabRepoScript extraction)
- **Issue:** Python script incorrectly added `-ScriptDir $ScriptDir -RunEvents $RunEvents` after closing `}` of scriptblocks passed to Invoke-MenuCommand, attaching params to wrong function
- **Fix:** Manually corrected 9 menu handler lines to place params inside the scriptblock
- **Files modified:** OpenCodeLab-App.ps1
- **Verification:** Grep confirms all Invoke-LabRepoScript calls have correct params
- **Committed in:** 3b6ed5a (Task 4 commit)

**3. [Rule 1 - Bug] Updated DeployModeHandoff tests after function extraction**
- **Found during:** Task 10 (full test suite run)
- **Issue:** DeployModeHandoff.Tests.ps1 checked for inline Get-BootstrapArgs/Get-DeployArgs in App.ps1; those are now in Private/
- **Fix:** Updated tests to read Private/Get-LabBootstrapArgs.ps1 and Private/Get-LabDeployArgs.ps1 for structural assertions
- **Files modified:** Tests/DeployModeHandoff.Tests.ps1
- **Verification:** All 11 DeployModeHandoff tests pass; 612 total pass
- **Committed in:** c87eb82 (Task 10 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 bugs)
**Impact on plan:** All fixes necessary for correctness. No scope creep.

## Issues Encountered

- PowerShell silently drops `@()` values when storing to variables (empty array becomes `$null`). Unit tests for Get-LabPreflightArgs and Get-LabHealthArgs had to use `@($result).Count` instead of type assertions.

## Next Phase Readiness

- Batch 1 extraction complete (11 functions). Batch 2 (08-02) can proceed.
- Private/ auto-loader (Lab-Common.ps1 via Import-LabScriptTree) picks up all new files automatically.
- Remaining inline functions in App.ps1: ~23 (down from 34 before this batch).

## Self-Check: PASSED

- All 12 created files exist (11 Private/ + 1 test file)
- All 10 task commits verified in git log
- Full test suite: 612 pass, 0 fail, 8 skip

---
*Phase: 08-orchestrator-extraction*
*Completed: 2026-02-17*
