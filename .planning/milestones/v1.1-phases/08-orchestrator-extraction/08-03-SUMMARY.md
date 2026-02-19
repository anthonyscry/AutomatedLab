---
phase: 08-orchestrator-extraction
plan: 03
subsystem: orchestrator
tags: [powershell, extraction, lifecycle, refactoring, pester]

# Dependency graph
requires:
  - phase: 08-orchestrator-extraction (08-01)
    provides: "11 pure utility functions in Private/ (Add-LabRunEvent, Invoke-LabRepoScript, Get-LabBootstrapArgs, etc.)"
  - phase: 08-orchestrator-extraction (08-02)
    provides: "8 state/ops functions in Private/ (Invoke-LabBlowAway, Invoke-LabQuickDeploy, Invoke-LabQuickTeardown, etc.)"
provides:
  - "Invoke-LabOrchestrationActionCore: central deploy/teardown dispatch with explicit params"
  - "Invoke-LabOneButtonSetup: full one-button setup sequence with rollback support"
  - "Invoke-LabOneButtonReset: blow-away + rebuild sequence with explicit params"
  - "Invoke-LabSetup: preflight + bootstrap sequence with explicit params"
  - "Invoke-LabBulkVMProvision: bulk server/workstation VM provisioning with LabConfig param"
  - "Invoke-LabSetupMenu: interactive setup menu with explicit params"
  - "27 new Pester unit tests for all 6 functions"
affects:
  - 08-04-PLAN (Batch 4 interactive menu functions)
  - 09-error-handling (will use extracted lifecycle functions)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "All lifecycle orchestration functions accept explicit params (no script-scope reads)"
    - "LabConfig hashtable passed as parameter replacing GlobalLabConfig reads"
    - "Fake Hyper-V module via New-Module for testing module-qualified cmdlets"
    - "Read-MenuCount stubbed in tests until Batch 4 extraction"

key-files:
  created:
    - Private/Invoke-LabOrchestrationActionCore.ps1
    - Private/Invoke-LabOneButtonSetup.ps1
    - Private/Invoke-LabOneButtonReset.ps1
    - Private/Invoke-LabSetup.ps1
    - Private/Invoke-LabBulkVMProvision.ps1
    - Private/Invoke-LabSetupMenu.ps1
    - Tests/OrchestratorExtraction-Batch3.Tests.ps1
  modified:
    - OpenCodeLab-App.ps1
    - Tests/CLIActionRouting.Tests.ps1
    - Tests/TeardownIdempotency.Tests.ps1
    - Tests/DeployModeHandoff.Tests.ps1

key-decisions:
  - "Invoke-LabSetupMenu calls Read-MenuCount by current name (not yet extracted); Batch 4 will rename it"
  - "Hyper-V module-qualified calls cannot be Pester-mocked; fake Hyper-V module via New-Module used in tests"
  - "Tests checking App.ps1 inline definitions updated to check Private/ files after extraction (same pattern as 08-02)"
  - "Invoke-LabBulkVMProvision tests use temp dir on local filesystem to avoid Windows C: drive paths on WSL"

patterns-established:
  - "Extracted functions use LabConfig hashtable param instead of $GlobalLabConfig script-scope"
  - "App.ps1 call sites updated to pass explicit params: LabConfig $GlobalLabConfig, ScriptDir $ScriptDir, etc."
  - "Module-qualified cmdlets (Hyper-V\\Get-VM) tested via fake module injection, not Pester mocking"

requirements-completed:
  - EXT-01
  - EXT-03
  - EXT-04

# Metrics
duration: 34min
completed: 2026-02-17
---

# Phase 8 Plan 03: Orchestrator Extraction Batch 3 Summary

**6 lifecycle orchestration functions extracted from OpenCodeLab-App.ps1 to Private/ with explicit params, 27 tests, 670 total passing**

## Performance

- **Duration:** 34 min
- **Started:** 2026-02-17T04:51:47Z
- **Completed:** 2026-02-17T05:25:27Z
- **Tasks:** 8
- **Files modified:** 11

## Accomplishments
- Extracted 6 lifecycle orchestration functions (Invoke-LabOrchestrationActionCore, Invoke-LabOneButtonSetup, Invoke-LabOneButtonReset, Invoke-LabSetup, Invoke-LabBulkVMProvision, Invoke-LabSetupMenu) to Private/ with explicit parameters
- Each function uses LabConfig, ScriptDir, RunEvents etc. as explicit params instead of reading script-scope globals
- Created 27 unit tests covering all 6 functions; fake Hyper-V module pattern for module-qualified cmdlet testing
- Updated 3 existing regression tests to check Private/ files after extraction; all 670 tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract Invoke-LabOrchestrationActionCore** - `f742066` (feat)
2. **Task 2: Extract Invoke-LabOneButtonSetup** - `9d6bc11` (feat)
3. **Task 3: Extract Invoke-LabOneButtonReset** - `5549c2b` (feat)
4. **Task 4: Extract Invoke-LabSetup** - `bfb6663` (feat)
5. **Task 5: Extract Invoke-LabBulkVMProvision** - `a8c4851` (feat)
6. **Task 6: Extract Invoke-LabSetupMenu** - `6bd923e` (feat)
7. **Task 7: Create unit tests** - `63f82e2` (test)
8. **Task 8: Fix regression tests** - `c0f1383` (fix)

## Files Created/Modified
- `Private/Invoke-LabOrchestrationActionCore.ps1` - Central deploy/teardown dispatch with explicit params
- `Private/Invoke-LabOneButtonSetup.ps1` - Full setup sequence: preflight -> bootstrap -> health check with rollback
- `Private/Invoke-LabOneButtonReset.ps1` - Blow-away + one-button setup sequence
- `Private/Invoke-LabSetup.ps1` - Preflight + bootstrap only (no health check)
- `Private/Invoke-LabBulkVMProvision.ps1` - Bulk server/workstation VM provisioning with LabConfig param
- `Private/Invoke-LabSetupMenu.ps1` - Interactive setup menu (server/workstation count prompts)
- `Tests/OrchestratorExtraction-Batch3.Tests.ps1` - 27 unit tests for all 6 functions
- `OpenCodeLab-App.ps1` - Removed 6 inline function definitions; updated all call sites with explicit params
- `Tests/CLIActionRouting.Tests.ps1` - Updated to check Invoke-LabBulkVMProvision in Private/
- `Tests/TeardownIdempotency.Tests.ps1` - Updated to check Invoke-LabOneButtonReset in Private/
- `Tests/DeployModeHandoff.Tests.ps1` - Updated deploy mode checks for extracted functions

## Decisions Made
- `Invoke-LabSetupMenu` calls `Read-MenuCount` by current name (not yet extracted; Batch 4 will rename it to `Read-LabMenuCount`)
- `Hyper-V\Get-VM` module-qualified calls can't be mocked by Pester; solved by creating a fake Hyper-V module via `New-Module` in test setup
- Tests that checked App.ps1 inline definitions updated to check Private/ files (same pattern as 08-02)
- `Invoke-LabBulkVMProvision` tests use temp path on Linux filesystem (not `C:\`) to work on WSL

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated existing regression tests after extraction**
- **Found during:** Task 8 (full test suite regression check)
- **Issue:** CLIActionRouting, TeardownIdempotency, and DeployModeHandoff tests checked App.ps1 for inline function definitions that were extracted to Private/; 4 tests failing
- **Fix:** Redirected tests to check Private/ files; updated function names and counts
- **Files modified:** Tests/CLIActionRouting.Tests.ps1, Tests/TeardownIdempotency.Tests.ps1, Tests/DeployModeHandoff.Tests.ps1
- **Verification:** All 670 tests pass
- **Committed in:** c0f1383 (Task 8 commit)

**2. [Rule 1 - Bug] Pester cannot mock module-qualified Hyper-V\\Get-VM**
- **Found during:** Task 7 (unit test creation)
- **Issue:** Tests using `Mock Hyper-V\Get-VM` failed with CommandNotFoundException; Pester can't intercept module-qualified calls
- **Fix:** Created fake Hyper-V module via `New-Module -Name 'Hyper-V' ...` in BeforeAll; removed `Mock Hyper-V\Get-VM` from tests; restructured Invoke-LabBulkVMProvision tests to use temp dir instead of C:\ paths
- **Files modified:** Tests/OrchestratorExtraction-Batch3.Tests.ps1
- **Verification:** All 27 batch 3 tests pass
- **Committed in:** 63f82e2 (Task 7 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - test infrastructure fixes)
**Impact on plan:** Both fixes required for test correctness. No scope creep. No behavior changes.

## Issues Encountered
- WSL environment has no C: drive; Invoke-LabBulkVMProvision tests using `C:\TestLabRoot` as LabConfig.Paths.LabRoot failed with `Cannot find drive`. Fixed by using temp dir from `[System.IO.Path]::GetTempPath()`.

## Next Phase Readiness
- Batch 3 (6 lifecycle functions) complete; all extracted to Private/ with explicit params
- OpenCodeLab-App.ps1 down to interactive menu system functions (Batch 4: ~9 functions)
- 670 tests passing, no regressions
- Batch 4 (08-04) ready: Pause-Menu, Invoke-MenuCommand, Get-MenuVmSelection, Invoke-ConfigureRoleMenu, Invoke-AddVMWizard, Invoke-AddVMMenu, Read-MenuCount, Show-Menu, Invoke-InteractiveMenu

---
*Phase: 08-orchestrator-extraction*
*Completed: 2026-02-17*
